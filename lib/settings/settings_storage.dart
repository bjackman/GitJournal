/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:android_external_storage/android_external_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gitjournal/core/folder/notes_folder_config.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/features.dart';
import 'package:gitjournal/l10n.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:gitjournal/repository.dart';
import 'package:gitjournal/settings/settings.dart';
import 'package:gitjournal/settings/settings_filetypes.dart';
import 'package:gitjournal/settings/settings_images.dart';
import 'package:gitjournal/settings/settings_note_metadata.dart';
import 'package:gitjournal/settings/settings_tags.dart';
import 'package:gitjournal/settings/storage_config.dart';
import 'package:gitjournal/settings/widgets/settings_header.dart';
import 'package:gitjournal/settings/widgets/settings_list_preference.dart';
import 'package:gitjournal/utils/utils.dart';
import 'package:gitjournal/widgets/folder_selection_dialog.dart';
import 'package:gitjournal/widgets/pro_overlay.dart';
import 'package:icloud_documents_path/icloud_documents_path.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:universal_io/io.dart';

class SettingsStorageScreen extends StatelessWidget {
  static const routePath = '/settings/storage';

  const SettingsStorageScreen({super.key});
  @override
  Widget build(BuildContext context) {
    var folderConfig = Provider.of<NotesFolderConfig>(context);
    var storageConfig = Provider.of<StorageConfig>(context);
    final repo = Provider.of<GitJournalRepo>(context);
    var settings = Provider.of<Settings>(context);

    var list = ListView(
      children: [
        ListPreference(
          title: context.loc.settingsNoteNewNoteFileName,
          currentOption: folderConfig.fileNameFormat.toPublicString(context),
          options: NoteFileNameFormat.options
              .map((f) => f.toPublicString(context))
              .toList(),
          onChange: (String publicStr) {
            var format =
                NoteFileNameFormat.fromPublicString(context, publicStr);
            folderConfig.fileNameFormat = format;
            folderConfig.save();
          },
        ),
        const DefaultFileFormatTile(),
        const DefaultNoteFolderTile(),
        ListTile(
          title: Text(context.loc.settingsNoteMetaDataTitle),
          subtitle: Text(context.loc.settingsNoteMetaDataSubtitle),
          onTap: () {
            var route = MaterialPageRoute(
              builder: (context) => NoteMetadataSettingsScreen(),
              settings: const RouteSettings(
                name: NoteMetadataSettingsScreen.routePath,
              ),
            );
            var _ = Navigator.push(context, route);
          },
        ),
        ListTile(
          title: Text(context.loc.settingsFileTypesTitle),
          subtitle: Text(context.loc.settingsFileTypesSubtitle),
          onTap: () {
            var route = MaterialPageRoute(
              builder: (context) => const NoteFileTypesSettings(),
              settings: const RouteSettings(
                name: NoteFileTypesSettings.routePath,
              ),
            );
            var _ = Navigator.push(context, route);
          },
        ),
        ProOverlay(
          feature: Feature.inlineTags,
          child: ListTile(
            title: Text(context.loc.settingsTagsTitle),
            subtitle: Text(context.loc.settingsTagsSubtitle),
            onTap: () {
              var route = MaterialPageRoute(
                builder: (context) => const SettingsTagsScreen(),
                settings:
                    const RouteSettings(name: SettingsTagsScreen.routePath),
              );
              var _ = Navigator.push(context, route);
            },
          ),
        ),
        ListTile(
          title: Text(context.loc.settingsImagesTitle),
          subtitle: Text(context.loc.settingsImagesSubtitle),
          onTap: () {
            var route = MaterialPageRoute(
              builder: (context) => SettingsImagesScreen(),
              settings: const RouteSettings(
                name: SettingsImagesScreen.routePath,
              ),
            );
            var _ = Navigator.push(context, route);
          },
        ),
        SettingsHeader(context.loc.settingsStorageTitle),
        if (Platform.isAndroid)
          SwitchListTile(
            title: Text(context.loc.settingsStorageExternal),
            value: !storageConfig.storeInternally,
            onChanged: (bool newVal) async {
              Future<void> moveBackToInternal(bool showError) async {
                storageConfig.storeInternally = true;
                storageConfig.storageLocation = "";

                storageConfig.save();
                await repo.moveRepoToPath();

                if (showError) {
                  showErrorMessageSnackbar(
                    context,
                    context.loc.settingsStorageFailedExternal,
                  );
                }
              }

              if (newVal == false) {
                await moveBackToInternal(false);
              } else {
                var path = await _getExternalDir(context);
                if (path.isEmpty) {
                  await moveBackToInternal(false);
                  return;
                }

                Log.i("Moving repo to $path");

                storageConfig.storeInternally = false;
                storageConfig.storageLocation = path;
                storageConfig.save();

                try {
                  await repo.moveRepoToPath();
                } catch (ex, st) {
                  Log.e("Moving Repo to External Storage",
                      ex: ex, stacktrace: st);
                  await moveBackToInternal(true);
                  return;
                }
                return;
              }
            },
          ),
        if (Platform.isAndroid)
          ListTile(
            title: Text(context.loc.settingsStorageRepoLocation),
            subtitle: Text(p.join(
                storageConfig.storageLocation, storageConfig.folderName)),
            enabled: !storageConfig.storeInternally,
          ),
        if (Platform.isIOS)
          SwitchListTile(
            title: Text(context.loc.settingsStorageIcloud),
            value: !storageConfig.storeInternally,
            onChanged: (bool newVal) async {
              if (newVal == false) {
                storageConfig.storeInternally = true;
                storageConfig.storageLocation = "";
              } else {
                storageConfig.storageLocation =
                    (await ICloudDocumentsPath.documentsPath)!;
                if (storageConfig.storageLocation.isNotEmpty) {
                  storageConfig.storeInternally = false;
                }
              }
              settings.save();
              repo.moveRepoToPath();
            },
          ),
        if (Platform.isLinux || Platform.isMacOS)
          ListTile(
            title: Text(context.loc.settingsStorageRepoLocation),
            subtitle: Text(repo.repoPath),
            enabled: !storageConfig.storeInternally,
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.settingsListStorageTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: list,
    );
  }
}

Future<bool> _isDirWritable(String path) async {
  var fileName = DateTime.now().millisecondsSinceEpoch.toString();
  var file = File(p.join(path, fileName));

  try {
    dynamic _;
    _ = await file.writeAsString("test");
    _ = await file.delete();
  } catch (_) {
    return false;
  }

  return true;
}

Future<String> _getExternalDir(BuildContext context) async {
  if (!await Permission.storage.request().isGranted) {
    Log.e("Storage Permission Denied");
    showErrorMessageSnackbar(
      context,
      context.loc.settingsStoragePermissionFailed,
    );
    return "";
  }

  var dir = await FilePicker.platform.getDirectoryPath();
  if (dir != null && dir.isNotEmpty) {
    if (await _isDirWritable(dir)) {
      return dir;
    } else {
      Log.e("FilePicker: Got $dir but it is not writable");
      showErrorMessageSnackbar(
        context,
        context.loc.settingsStorageNotWritable(dir),
      );
    }
  }

  var path = await AndroidExternalStorage.getExternalStorageDirectory();
  if (path != null) {
    if (await _isDirWritable(path)) {
      return path;
    } else {
      Log.e("ExtStorage: Got $path but it is not writable");
    }
  }

  var extDir = await getExternalStorageDirectory();
  if (extDir != null) {
    path = extDir.path;

    if (await _isDirWritable(path)) {
      return path;
    } else {
      Log.e("ExternalStorageDirectory: Got $path but it is not writable");
    }
  }

  return "";
}

class DefaultNoteFolderTile extends StatelessWidget {
  const DefaultNoteFolderTile({super.key});

  @override
  Widget build(BuildContext context) {
    var settings = Provider.of<Settings>(context);

    var defaultNewFolder = settings.defaultNewNoteFolderSpec;
    if (defaultNewFolder.isEmpty) {
      defaultNewFolder = context.loc.rootFolder;
    } else {
      // Reset the settings in case the folder no longer exists
      if (!folderWithSpecExists(context, defaultNewFolder)) {
        defaultNewFolder = context.loc.rootFolder;

        settings.defaultNewNoteFolderSpec = "";
        settings.save();
      }
    }

    return ListTile(
      title: Text(context.loc.settingsNoteDefaultFolder),
      subtitle: Text(defaultNewFolder),
      onTap: () async {
        var destFolder = await showDialog<NotesFolderFS>(
          context: context,
          builder: (context) => FolderSelectionDialog(),
        );
        if (destFolder != null) {
          settings.defaultNewNoteFolderSpec = destFolder.folderPath;
          settings.save();
        }
      },
    );
  }
}

class DefaultFileFormatTile extends StatelessWidget {
  const DefaultFileFormatTile({super.key});

  @override
  Widget build(BuildContext context) {
    var folderConfig = Provider.of<NotesFolderConfig>(context);

    return ListPreference(
      title: context.loc.settingsEditorsDefaultNoteFormat,
      currentOption: folderConfig.defaultFileFormat.toPublicString(context),
      options: SettingsNoteFileFormat.options
          .map((f) => f.toPublicString(context))
          .toList(),
      onChange: (String publicStr) {
        var val = SettingsNoteFileFormat.fromPublicString(context, publicStr);
        folderConfig.defaultFileFormat = val;
        folderConfig.save();
      },
    );
  }
}
