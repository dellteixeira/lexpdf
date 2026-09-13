# LexPDF compatibility patch

'
    'Vendored from `exusr/fluent-editor` at commit '
    '`5676354889f7d5554458c9e97a85cfe640c4a133` (version 1.1.0).

'
    'LexPDF uses `archive` 4.x because its PDF document stack requires it. '
    'The upstream editor still declares `archive ^3.6.1` and uses the removed '
    '`ArchiveFile.compress` setter for the ODT mimetype entry. This vendor patch '
    'updates the constraint to `archive ^4.0.5` and uses '
    '`ArchiveFile.noCompress`, preserving the ODT requirement that `mimetype` '
    'is stored uncompressed.

'
    'The upstream editor also declares `file_picker ^8.0.0`. That resolves to '
    '`file_picker 8.3.7`, whose Android library is compiled against API 34 and '
    'fails AAR metadata validation when `flutter_plugin_android_lifecycle` requires '
    'API 36. LexPDF pins the published `file_picker 10.3.10`, which retains the '
    '10.x instance API used by Fluent Editor, uses Flutter compileSdk, and contains '
    'the Gradle 9 compatibility work from the 10.3.9 line.

'
    'The upstream MIT LICENSE is retained in this directory.
