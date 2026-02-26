#!/bin/sh
BUILD_NAME="picolua-pim2w"
BUILD_NUM=$1
DEPLOY=/home/steve/dev/picocalc/uf2-deploy
rm -rf build

if ! PICO_SDK_PATH=/home/steve/dev/picocalc/pico-sdk cmake -DPICO_BOARD=pimoroni_pico_plus2_w_rp2350 -B build -S . ; then
  echo "*** cmake failed ***"
  exit 1
else
  echo "cmake succeeded!"
fi

echo "entering build directory"
cd build

echo "running 'make' and copying uf2 to $DEPLOY..."
if make -j$(nproc); then
  echo "build command succeeded!"
else
  echo "*** build command failed ***"
fi

echo "copying $BUILD_NAME-$BUILD_NUM.uf2 to $DEPLOY..."
if cp picolua.uf2 $DEPLOY/$BUILD_NAME-$BUILD_NUM.uf2; then
  echo "all done!"
else
  echo "*** copying uf2 to $DEPLOY failed ***"
fi
