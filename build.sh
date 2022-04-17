#!/bin/bash

mksquashfs "installed-modules/lib/" "modloop" -b 1048576 -comp xz -Xdict-size 100% -all-root
