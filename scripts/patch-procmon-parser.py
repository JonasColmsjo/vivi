#!/usr/bin/env python3
"""Patch procmon-parser to decode SetRenameInformationFile details.

The upstream procmon-parser library is missing a handler for
SetRenameInformationFile events, so the rename target filename
is lost (details returns empty OrderedDict).

This script patches the installed library in-place to add the
missing handler. Safe to re-run — it checks if already patched.

Usage:
    python3 patch-procmon-parser.py [--check] [--revert]

The patch target is:
    <site-packages>/procmon_parser/stream_logs_detail_format.py
"""
import sys
import importlib
import inspect
import argparse

PATCH_MARKER = "# PATCH: SetRenameInformationFile handler"

HANDLER_CODE = '''
# PATCH: SetRenameInformationFile handler
# Decodes the rename target filename from the io stream.
# Structure: ReplaceIfExists (1 byte) + padding (7 bytes) +
#            FileNameLength (4 bytes, in bytes) + FileName (UTF-16LE)
def get_filesystem_setrenameinformation_details(io, metadata, event, details_io, extra_detail_io):
    remaining = io.read()
    if len(remaining) < 12:
        return
    replace_if_exists = bool(remaining[0])
    filename_length = int.from_bytes(remaining[8:12], "little")
    if filename_length > 0 and 12 + filename_length <= len(remaining):
        raw = remaining[12:12 + filename_length]
        try:
            filename = raw.decode("utf-16-le").rstrip("\\x00")
            # Strip \\??\\ prefix if present
            if filename.startswith("\\\\??\\\\"):
                filename = filename[4:]
            event.details["FileName"] = filename
        except UnicodeDecodeError:
            event.details["FileName"] = f"<decode error, {filename_length} bytes>"
    if replace_if_exists:
        event.details["ReplaceIfExists"] = "True"
    event.category = "Write"
'''

REGISTRATION_LINE = (
    "    FilesystemSetInformationOperation.SetRenameInformationFile.name:\n"
    "        get_filesystem_setrenameinformation_details,\n"
)


def find_source():
    import procmon_parser.stream_logs_detail_format as mod
    return inspect.getfile(mod)


def is_patched(source):
    with open(source) as f:
        return PATCH_MARKER in f.read()


def apply_patch(source):
    with open(source) as f:
        content = f.read()

    # 1. Add handler function before FilesystemSubOperationHandler dict
    anchor = "FilesystemSubOperationHandler = {"
    if anchor not in content:
        print(f"ERROR: Cannot find '{anchor}' in {source}", file=sys.stderr)
        sys.exit(1)
    content = content.replace(anchor, HANDLER_CODE + "\n" + anchor)

    # 2. Add registration in the dict (after SetDispositionInformationFile entry)
    reg_anchor = "        get_filesystem_setdispositioninformation_details,"
    if reg_anchor not in content:
        print(f"ERROR: Cannot find SetDisposition registration in {source}", file=sys.stderr)
        sys.exit(1)
    content = content.replace(
        reg_anchor,
        reg_anchor + "\n" + REGISTRATION_LINE.rstrip("\n"),
    )

    with open(source, "w") as f:
        f.write(content)
    print(f"Patched: {source}")


def revert_patch(source):
    with open(source) as f:
        lines = f.readlines()

    # Remove handler function
    out = []
    skip = False
    for line in lines:
        if PATCH_MARKER in line:
            skip = True
            continue
        if skip:
            if line.startswith("def ") or (line.strip() == "" and not skip):
                skip = False
            elif line.strip().startswith("FilesystemSubOperationHandler"):
                skip = False
            else:
                continue
        # Remove registration line
        if "get_filesystem_setrenameinformation_details" in line:
            continue
        out.append(line)

    with open(source, "w") as f:
        f.writelines(out)
    print(f"Reverted: {source}")


def main():
    parser = argparse.ArgumentParser(description="Patch procmon-parser for SetRenameInformationFile")
    parser.add_argument("--check", action="store_true", help="Check if patched, exit 0 if yes")
    parser.add_argument("--revert", action="store_true", help="Revert the patch")
    args = parser.parse_args()

    source = find_source()
    patched = is_patched(source)

    if args.check:
        if patched:
            print(f"Already patched: {source}")
            sys.exit(0)
        else:
            print(f"Not patched: {source}")
            sys.exit(1)

    if args.revert:
        if not patched:
            print("Not patched, nothing to revert.")
            return
        revert_patch(source)
        return

    if patched:
        print(f"Already patched: {source}")
        return

    apply_patch(source)
    print("Done. SetRenameInformationFile events now include 'FileName' in details.")


if __name__ == "__main__":
    main()
