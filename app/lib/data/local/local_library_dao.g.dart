// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_library_dao.dart';

// ignore_for_file: type=lint
mixin _$LocalLibraryDaoMixin on DatabaseAccessor<AppDatabase> {
  $LocalMangaTable get localManga => attachedDatabase.localManga;
  $LocalCategoryTable get localCategory => attachedDatabase.localCategory;
  $LocalMangaCategoryTable get localMangaCategory =>
      attachedDatabase.localMangaCategory;
  $LocalImportRecordTable get localImportRecord =>
      attachedDatabase.localImportRecord;
  $LocalMangaImportTable get localMangaImport =>
      attachedDatabase.localMangaImport;
  $SyncMetaTable get syncMeta => attachedDatabase.syncMeta;
  LocalLibraryDaoManager get managers => LocalLibraryDaoManager(this);
}

class LocalLibraryDaoManager {
  final _$LocalLibraryDaoMixin _db;
  LocalLibraryDaoManager(this._db);
  $$LocalMangaTableTableManager get localManga =>
      $$LocalMangaTableTableManager(_db.attachedDatabase, _db.localManga);
  $$LocalCategoryTableTableManager get localCategory =>
      $$LocalCategoryTableTableManager(_db.attachedDatabase, _db.localCategory);
  $$LocalMangaCategoryTableTableManager get localMangaCategory =>
      $$LocalMangaCategoryTableTableManager(
        _db.attachedDatabase,
        _db.localMangaCategory,
      );
  $$LocalImportRecordTableTableManager get localImportRecord =>
      $$LocalImportRecordTableTableManager(
        _db.attachedDatabase,
        _db.localImportRecord,
      );
  $$LocalMangaImportTableTableManager get localMangaImport =>
      $$LocalMangaImportTableTableManager(
        _db.attachedDatabase,
        _db.localMangaImport,
      );
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db.attachedDatabase, _db.syncMeta);
}
