import 'dart:io';
import 'package:flutter/material.dart';

import '../../data/upload_exts.dart';
import '../../models/chat_models.dart';
import '../../theme/ds_icons.dart';
import '../../theme/ds_theme.dart';

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Colored 28x28 file type badge matching `FileIcon.tsx`.
class DsFileIcon extends StatelessWidget {
  final String filename;
  final bool isImage;
  final double size;

  const DsFileIcon({
    super.key,
    required this.filename,
    required this.isImage,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final ext = getFileExt(filename);
    Color bg;
    IconData icon;
    if (isImage) {
      bg = DsFileColors.image;
      icon = Icons.image_outlined;
    } else if (ext == 'pdf') {
      bg = DsFileColors.pdf;
      icon = Icons.picture_as_pdf_outlined;
    } else if (ext == 'xls' || ext == 'xlsx' || ext == 'csv' || ext == 'tsv') {
      bg = DsFileColors.spreadsheet;
      icon = Icons.table_chart_outlined;
    } else if (ext == 'ppt' || ext == 'pptx') {
      bg = DsFileColors.presentation;
      icon = Icons.slideshow_outlined;
    } else {
      bg = DsFileColors.document;
      icon = Icons.description_outlined;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.58, color: Colors.white),
    );
  }
}

/// Document attachment card (`240 x 64`, `border-radius: 16px`).
class DsFileCard extends StatelessWidget {
  final FileAttachment file;
  final DraftUploadStatus? uploadStatus;
  final String? errorMessage;
  final bool retryable;
  final VoidCallback? onRemove;
  final VoidCallback? onRetry;

  const DsFileCard({
    super.key,
    required this.file,
    this.uploadStatus,
    this.errorMessage,
    this.retryable = true,
    this.onRemove,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final isError = uploadStatus == DraftUploadStatus.error;
    final isUploading = uploadStatus == DraftUploadStatus.uploading;
    final ext = getFileExt(file.name).toUpperCase();
    final meta = ext.isEmpty
        ? formatFileSize(file.size)
        : '$ext ${formatFileSize(file.size)}';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: isError && retryable ? onRetry : null,
          child: Container(
            width: 224,
            height: 64,
            padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
            decoration: BoxDecoration(
              color: ds.inputMajor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isError ? ds.errorPrimary : ds.borderL2,
              ),
            ),
            child: Row(
              children: [
                if (isUploading)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ds.brandPrimary,
                      ),
                    ),
                  )
                else if (isError && retryable)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: ds.errorPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: DsIcons.svg(
                      DsIcons.refresh,
                      size: 16,
                      color: ds.errorPrimary,
                    ),
                  )
                else
                  DsFileIcon(filename: file.name, isImage: file.isImage),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 20 / 14,
                          color: ds.labelPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isError ? (errorMessage ?? 'Error') : meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 16 / 12,
                          color: isError ? ds.errorPrimary : ds.labelTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 4,
            right: 4,
            child: _RemoveBadge(
              isError: isError && !retryable,
              onTap: onRemove!,
            ),
          ),
      ],
    );
  }
}

/// Image thumbnail (`64x64` in composer/mixed, `120x120` in image-only user messages).
class DsImageAttachmentTile extends StatelessWidget {
  final FileAttachment file;
  final double size;
  final DraftUploadStatus? uploadStatus;
  final String? errorMessage;
  final bool retryable;
  final VoidCallback? onRemove;
  final VoidCallback? onRetry;
  final VoidCallback? onTap;

  const DsImageAttachmentTile({
    super.key,
    required this.file,
    this.size = 64,
    this.uploadStatus,
    this.errorMessage,
    this.retryable = true,
    this.onRemove,
    this.onRetry,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final isError = uploadStatus == DraftUploadStatus.error;
    final isUploading = uploadStatus == DraftUploadStatus.uploading;
    final localFile =
        file.localPath != null ? File(file.localPath!) : null;
    final exists = localFile != null && localFile.existsSync();

    return Stack(
      children: [
        GestureDetector(
          onTap: isError && retryable ? onRetry : onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: ds.citationBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isError ? ds.errorPrimary : ds.borderL2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (exists)
                  Image.file(
                    localFile,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallback(ds),
                  )
                else
                  _fallback(ds),
                if (isUploading)
                  Container(
                    color: Colors.black.withValues(alpha: 0.32),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (isError)
                  Container(
                    color: Colors.black.withValues(
                      alpha: retryable ? 0.48 : 0.28,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (retryable)
                          DsIcons.svg(
                            DsIcons.refresh,
                            size: 16,
                            color: Colors.white,
                          ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            errorMessage!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              height: 1.2,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 4,
            right: 4,
            child: _RemoveBadge(
              isError: isError && !retryable,
              onTap: onRemove!,
            ),
          ),
      ],
    );
  }

  Widget _fallback(DsColors ds) {
    return Center(
      child: Icon(
        Icons.broken_image_outlined,
        size: 22,
        color: ds.labelTertiary,
      ),
    );
  }
}

class _RemoveBadge extends StatelessWidget {
  final bool isError;
  final VoidCallback onTap;

  const _RemoveBadge({required this.isError, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: isError ? ds.errorPrimary : ds.buttonContrastFill,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.close,
          size: 12,
          color: isError
              ? Colors.white
              : (ds.isDark ? const Color(0xFF1B1B1C) : Colors.white),
        ),
      ),
    );
  }
}
