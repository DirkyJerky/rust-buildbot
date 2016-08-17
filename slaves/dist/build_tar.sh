#!/bin/bash

set -ex

VERSION=1.29
SHA256=236b11190c0a3a6885bdb8d61424f2b36a5872869aa3f7f695dea4b4843ae2f2

curl https://ftp.gnu.org/gnu/tar/tar-$VERSION.tar.bz2 | \
  tee >(sha256sum > tar-$VERSION.tar.bz2.sha256)      | tar xjf -
test $SHA256 = $(cut -d ' ' -f 1 tar-$VERSION.tar.bz2.sha256) || exit 1

mkdir tar-build
cd tar-build

# The weird _FORTIFY_SOURCE option here is passed as a last-ditch attempt to get
# this to build. Apparently there are some inline functions in
# /usr/include/bits/unistd.h which get emitted if _FORTIFY_SOURCE is bigger than
# 0, and apparently tar wants to set this value higher than 0 by default. We
# move it back to get things building (if it works without it though feel free!)
#
# We also pass FORCE_UNSAFE_CONFIGURE as apparently the configure script
# requires us to do that if we're running as root (which we are). Trust me
# though, "I got this".
CFLAGS=-D_FORTIFY_SOURCE=0 FORCE_UNSAFE_CONFIGURE=1 \
    ../tar-$VERSION/configure --prefix=/rustroot

make -j10
make install
yum erase -y tar

# Apparently tar's configure script creates this massive directory tree if a
# bunch of nested directories called 'confdir3'. This ends up thwarting rm -rf
# once we try to blow this directory away, which is generally not cool, so we
# use a small C program (shell doesn't work?) to just rename all confdir3
# directories to 'a' so rm -rf will succeed (path name limits shouldn't be hit).
cat > foo.c <<-EOF
#include <string.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <assert.h>
#include <unistd.h>

int main() {
        struct stat buf;

        while (stat("confdir3", &buf) == 0) {
                assert(chdir("confdir3") == 0);
        }
        assert(chdir("..") == 0);
        while (stat("confdir3", &buf) == 0) {
                assert(rename("confdir3", "a") == 0);
                assert(chdir("..") == 0);
        }
        return 0;
}
EOF
gcc foo.c
./a.out
