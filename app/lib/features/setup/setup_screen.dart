import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/entrance_fade.dart';
import '../../widgets/pill_button.dart';
import 'setup_controller.dart';

/// Route of the first-run server setup. Lives outside the tab shell — there is
/// no library to browse until it is done.
const String kSetupRoute = '/setup';

/// First-run screen: point the app at your own Manga Vault server.
///
/// This is the app's front door for someone who just sideloaded the APK, so it
/// carries the explanation too. The premise — *you run the server, we don't* —
/// is unusual enough that a bare pair of text fields would read as a login form
/// and send people looking for an account they never made.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key, this.isReconfiguring = false});

  /// Reached from About to change servers, rather than on first run. Adds a
  /// back route and softens the copy.
  final bool isReconfiguring;

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  final _tokenFocus = FocusNode();
  bool _revealToken = false;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(setupControllerProvider);
    _url = TextEditingController(text: initial.url);
    _token = TextEditingController(text: initial.token);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _tokenFocus.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    final ok = await ref.read(setupControllerProvider.notifier).submit();
    if (!mounted) return;
    if (ok) {
      // The router guard would bounce us anyway, but going explicitly means
      // the transition happens now rather than on the next navigation.
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setupControllerProvider);
    final controller = ref.read(setupControllerProvider.notifier);

    // The normalized URL can change under the field (a pasted `/api/v1` is
    // stripped); keep the box in step without fighting the user's cursor.
    if (_url.text != state.url && !_url.selection.isValid) {
      _url.text = state.url;
    }

    final cells = <Widget>[
      _IntroCell(isReconfiguring: widget.isReconfiguring),
      _FormCell(
        url: _url,
        token: _token,
        tokenFocus: _tokenFocus,
        state: state,
        revealToken: _revealToken,
        onUrlChanged: controller.setUrl,
        onTokenChanged: controller.setToken,
        onToggleReveal: () => setState(() => _revealToken = !_revealToken),
        onSubmit: state.canSubmit ? _connect : null,
      ),
      const _HelpCell(),
    ];

    return Scaffold(
      appBar: widget.isReconfiguring
          ? AppBar(title: const Text('Change server'))
          : null,
      body: SafeArea(
        child: ListView.separated(
          padding: EdgeInsets.fromLTRB(
            AppDimens.gutter,
            widget.isReconfiguring ? 0 : AppDimens.cellPadding,
            AppDimens.gutter,
            AppDimens.cellPadding * 2,
          ),
          itemCount: cells.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppDimens.gutter),
          itemBuilder: (context, index) => EntranceFade(
            delay: Duration(milliseconds: 80 * index),
            child: cells[index],
          ),
        ),
      ),
    );
  }
}

class _IntroCell extends StatelessWidget {
  const _IntroCell({required this.isReconfiguring});

  final bool isReconfiguring;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCell(
      tone: BentoTone.high,
      accent: VaultAccent.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AccentIconWell(
            icon: Icons.inventory_2_outlined,
            accent: VaultAccent.violet,
            size: 48,
            iconSize: 24,
          ),
          const SizedBox(height: AppDimens.unit * 2),
          Text(
            isReconfiguring ? 'Point somewhere\nelse' : 'Connect your\nvault',
            style: theme.textTheme.headlineLarge!.copyWith(height: 1.05),
          ),
          const SizedBox(height: AppDimens.unit + 4),
          Text(
            isReconfiguring
                ? 'Enter the address and token of the server you want to use. '
                    'The library cached on this device will be cleared and '
                    'pulled again from the new server.'
                : 'Manga Vault keeps your library on a server you run yourself '
                    '— there is no account and no Manga Vault cloud. Enter '
                    "your server's address and its API token to begin.",
            style: theme.textTheme.bodyMedium!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _FormCell extends StatelessWidget {
  const _FormCell({
    required this.url,
    required this.token,
    required this.tokenFocus,
    required this.state,
    required this.revealToken,
    required this.onUrlChanged,
    required this.onTokenChanged,
    required this.onToggleReveal,
    required this.onSubmit,
  });

  final TextEditingController url;
  final TextEditingController token;
  final FocusNode tokenFocus;
  final SetupState state;
  final bool revealToken;
  final ValueChanged<String> onUrlChanged;
  final ValueChanged<String> onTokenChanged;
  final VoidCallback onToggleReveal;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('Server address'),
          const SizedBox(height: AppDimens.unit),
          TextField(
            controller: url,
            onChanged: onUrlChanged,
            enabled: !state.isTesting,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => tokenFocus.requestFocus(),
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: '192.168.1.20:3000',
              errorText: state.urlError,
              // Two lines of error text are common here ("check the address
              // and that you are on the same network"); let them wrap rather
              // than clip.
              errorMaxLines: 3,
              prefixIcon: const Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: AppDimens.unit),
          Text(
            'Include the port. http:// is assumed if you leave it out.',
            style: theme.textTheme.bodyMedium!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDimens.unit * 3),
          const CellLabel('API token'),
          const SizedBox(height: AppDimens.unit),
          TextField(
            controller: token,
            focusNode: tokenFocus,
            onChanged: onTokenChanged,
            enabled: !state.isTesting,
            obscureText: !revealToken,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit?.call(),
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: 'Paste your API_TOKEN',
              errorText: state.tokenError,
              errorMaxLines: 3,
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                onPressed: onToggleReveal,
                tooltip: revealToken ? 'Hide token' : 'Show token',
                icon: Icon(
                  revealToken
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          if (state.generalError != null) ...[
            const SizedBox(height: AppDimens.unit * 2),
            NestedWell(
              accent: VaultAccent.rose,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 18,
                    color: VaultAccent.rose.color,
                  ),
                  const SizedBox(width: AppDimens.unit + 2),
                  Expanded(
                    child: Text(
                      state.generalError!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppDimens.unit * 3),
          // Fixed height so the cell doesn't jump when the label swaps to a
          // spinner mid-connect.
          SizedBox(
            height: 48,
            child: state.isTesting
                ? const _TestingIndicator()
                : Align(
                    alignment: Alignment.centerLeft,
                    child: PillButton(
                      label: 'Connect',
                      icon: Icons.link,
                      accent: VaultAccent.violet,
                      onPressed: onSubmit,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TestingIndicator extends StatelessWidget {
  const _TestingIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: VaultAccent.violet.color,
          ),
        ),
        const SizedBox(width: AppDimens.unit + 4),
        Text(
          'Contacting your server…',
          style: theme.textTheme.bodyMedium!
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Where to find the two values. Collapsed by default — it is only needed
/// once, and an expanded wall of setup text under the form makes the form look
/// harder than it is.
class _HelpCell extends StatelessWidget {
  const _HelpCell();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCell(
      accent: VaultAccent.cyan,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.cellPadding,
        vertical: AppDimens.unit,
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: AppDimens.unit * 2),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: theme.colorScheme.onSurfaceVariant,
          collapsedIconColor: theme.colorScheme.onSurfaceVariant,
          leading: const AccentIconWell(
            icon: Icons.help_outline,
            accent: VaultAccent.cyan,
          ),
          title: Text(
            'Where do I find these?',
            style: theme.textTheme.bodyLarge!
                .copyWith(fontWeight: FontWeight.w600),
          ),
          children: [
            _HelpStep(
              number: '1',
              title: 'Run the server',
              body: 'Manga Vault runs on a machine you control — a home '
                  'server, a NAS, or a small VM. Follow the deployment guide '
                  'in the project repository.',
            ),
            _HelpStep(
              number: '2',
              title: 'Address',
              body: 'The host and port the server listens on, for example '
                  '192.168.1.20:3000 on your home network, or '
                  'https://vault.example.com if you put it behind a domain.',
            ),
            _HelpStep(
              number: '3',
              title: 'API token',
              body: "The API_TOKEN value from your server's .env file. It is a "
                  'shared secret you choose yourself — treat it like a '
                  'password, and use a long random one.',
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  const _HelpStep({
    required this.number,
    required this.title,
    required this.body,
    this.isLast = false,
  });

  final String number;
  final String title;
  final String body;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppDimens.unit * 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: VaultAccent.cyan.color.withValues(alpha: AccentAlpha.fill),
              border: Border.all(
                color:
                    VaultAccent.cyan.color.withValues(alpha: AccentAlpha.border),
              ),
            ),
            child: Text(
              number,
              style: theme.textTheme.labelSmall!
                  .copyWith(color: VaultAccent.cyan.color),
            ),
          ),
          const SizedBox(width: AppDimens.unit + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge!
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium!
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
