#!/bin/sh

SQLITE_ARCHIVE=sqlite-amalgamation-3330000.zip
SQLITE_DOWNLOAD_URL=https://sqlite.org/2020/$SQLITE_ARCHIVE
SQLITE_DIR=$(basename "$SQLITE_ARCHIVE" .zip)

if ! [ -f "./$SQLITE_ARCHIVE" ]; then
        if ! [ -x "$(command -v curl)" ]; then
                echo "Error: $SQLITE_ARCHIVE not found and curl not present"
                echo "Please download sqlite manually from"
                echo "$SQLITE_DOWNLOAD_URL and re-run this script"
                exit 1
        fi

        curl -O "$SQLITE_DOWNLOAD_URL"
fi

/usr/bin/unzip -u "./$SQLITE_ARCHIVE"
rm -f sqlite
ln -s "./$SQLITE_DIR" sqlite

cd sqlite
cp shell.c shell.c.bk
split -p 'sqlite3_fileio_init.*p->db' shell.c part_
cat  part_aa ../fiesty_patch.txt part_ab > shell.c
rm part_*



