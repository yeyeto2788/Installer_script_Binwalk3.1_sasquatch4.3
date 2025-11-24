#!/bin/bash
set -e

clear
echo "==============================================="
echo "🔧 Binwalk 3.1 + SquashFS 4.3 Patch Installer"
echo "🔧 Script by  RickzDO"
echo "==============================================="


# Variables
HOME_DIR="$HOME"
BINWALK_DIR="$HOME_DIR/binwalk"
VENV_DIR="$HOME_DIR/venv_binwalk"
SASQ_SRC="$HOME_DIR/sasquatch"
BUILD_FILES_DIR="$HOME_DIR/build_files_sasquatch"
SQUASHFS_TAR="$HOME_DIR/squashfs4.3.tar.gz"
SQUASHFS_DIR="$HOME_DIR/squashfs4.3"
PATCH_FILE="$SASQ_SRC/patches/patch0.txt"

echo "=== 1. Limpiando instalaciones previas parciales (si existen) ==="
#Clean previous
rm -rf "$BINWALK_DIR" "$VENV_DIR" "$SASQ_SRC" "$BUILD_FILES_DIR" "$SQUASHFS_DIR" "$SQUASHFS_TAR"


echo "=== 2. Instalando dependencias del sistema necesarias ==="
sudo apt-get update
sudo apt-get install -y python3-venv build-essential liblzma-dev liblzo2-dev zlib1g-dev wget git patch mtd-utils gzip bzip2 tar arj p7zip-full p7zip-rar cabextract squashfs-tools sleuthkit lzop lhasa zstd libssl-dev pkg-config

echo "=== 3. Creando y activando entorno virtual para instalación ==="
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

echo "=== 4. Instalando Rust (mediante rustup) dentro del entorno virtual ==="
if ! command -v cargo &> /dev/null; then
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source "$HOME/.cargo/env"
fi

echo "=== 5. Actualizando pip, setuptools y wheel en entorno virtual ==="
pip install --upgrade pip setuptools wheel

echo "=== 6. Instalando paquetes Python necesarios en entorno virtual ==="
pip install kaleido toml six pyqt5 cstruct capstone pycrypto matplotlib numpy pyusb jefferson==0.4.6

echo "=== 7. Clonando o actualizando ReFirmLabs Binwalk ==="
if [ -d "$BINWALK_DIR" ]; then
    echo "El directorio binwalk ya existe, actualizando..."
    cd "$BINWALK_DIR"
    git pull
else
    git clone https://github.com/ReFirmLabs/binwalk.git "$BINWALK_DIR"
    cd "$BINWALK_DIR"
fi

echo "=== 8. Instalando binwalk usando Cargo (Rust) ==="
cargo install --path .

echo "=== 9. Instalando enlace simbólico global para binwalk ==="

BINWALK_BIN="$HOME/.cargo/bin/binwalk"
if [ -f "$BINWALK_BIN" ]; then
    sudo ln -sf "$BINWALK_BIN" /usr/local/bin/binwalk
    echo "Enlace simbólico creado en /usr/local/bin/binwalk"
else
    echo "[!] No se encontró binwalk en $BINWALK_BIN"
fi

echo "=== 10. Añadiendo ~/.cargo/bin al PATH en ~/.profile si no está ya ==="
if ! grep -q 'export PATH="$HOME/.cargo/bin:$PATH"' "$HOME/.profile"; then
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.profile"
    echo "Ruta ~/.cargo/bin añadida a ~/.profile"
fi

echo "=== 11. Clone Sasquatch repo and checkout PR56 branch ==="

if [ -d "$SASQ_SRC" ]; then
  cd "$SASQ_SRC"
  git fetch origin
else
  git clone https://github.com/devttys0/sasquatch.git "$SASQ_SRC"
  cd "$SASQ_SRC"
fi
git fetch origin pull/56/head:pr-56
git checkout pr-56

#  Download and extract squashfs4.3

echo "=== 12. Descarga & Extraccion de squashfs4.3 ==="
cd "$HOME_DIR"
if [ ! -f "$SQUASHFS_TAR" ]; then
  wget -O "$SQUASHFS_TAR" \
    https://downloads.sourceforge.net/project/squashfs/squashfs/squashfs4.3/squashfs4.3.tar.gz
fi
rm -rf "$SQUASHFS_DIR"
mkdir -p "$SQUASHFS_DIR"
tar -xzf "$SQUASHFS_TAR" -C "$SQUASHFS_DIR" --strip-components=1

echo "=== 12. Clona repo de RickDO y copia en squashfs-tools  ==="
if [ -d "$BUILD_FILES_DIR" ]; then
  cd "$BUILD_FILES_DIR" && git pull
else
  git clone https://github.com/RickzDO/build_-_Makefile_for_sasquatch.git "$BUILD_FILES_DIR"
fi

# Verifica si squashfs-tools existe
if [ ! -d "$SQUASHFS_DIR/squashfs-tools" ]; then
  echo "[!] ERROR: squashfs-tools directory not found in $SQUASHFS_DIR"
  exit 1
fi

# Replace the Makefile before applying the patch
cp -v "$BUILD_FILES_DIR/Makefile" "$SQUASHFS_DIR/squashfs-tools/Makefile"

# Check if dos2unix is installed, install it if not
if ! command -v dos2unix &>/dev/null; then
  echo "[i] dos2unix no encontrado. Instalando..."
  sudo apt-get update && sudo apt-get install -y dos2unix
fi

# Convierte formato a Unix
dos2unix "$SQUASHFS_DIR/squashfs-tools/Makefile"

#  Apply Patch AFTER replacing Makefile

if [ ! -f "$PATCH_FILE" ]; then
  echo "[!] ERROR: patch0.txt no encontrado en $PATCH_FILE"
  exit 1
fi

echo "=== 13. Aplicando parche a squashfs-tools ==="
cd "$SQUASHFS_DIR"
if ! patch -p0 < "$PATCH_FILE"; then
  echo "[⚠️] ADVERTENCIA: El parche no se aplicó completamente. Revisa squashfs-tools/Makefile.rej para ver los conflictos."
fi


#  Compile squashfs-tools
echo "=== 14. Compilando squashfs-tools ==="
cd squashfs-tools
make && sudo make install

#  Build Sasquatch binary itself
cd "$SASQ_SRC"
if [ -f Makefile ]; then
  make && sudo make install
fi

# Verify sasquatch binary is available
if command -v sasquatch &>/dev/null; then
  echo "✅ sasquatch available at $(which sasquatch)"
  sasquatch -v
  #  Final cleanup
  rm -rf "$SQUASHFS_DIR" "$SQUASHFS_TAR" "$BUILD_FILES_DIR"
  echo "=== 14. Installation complete! sasquatch is ready globally. ==="
else
  echo "[!] ERROR: sasquatch binary not found in PATH."
  exit 1
fi


