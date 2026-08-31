#!/usr/bin/env bash

# shellcheck source=frappe-bench-startup-common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/frappe-bench-startup-common.sh"
frappe_validate_ports || return 1

sudo chown frappe:frappe ../workspace

echo "alias ll='ls -al'" >> ~/.bashrc
echo "alias ll='ls -al'" >> ~/.bashrc
alias ll='ls -al'

sudo apt update

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

export NVM_DIR="$HOME/.nvm"
frappe_load_nvm || return 1

echo "installing Node v24"
nvm deactivate && nvm install 24 && nvm use 24 && nvm alias default 24 && nvm alias default node || return 1
frappe_resolve_node || return 1


npm install -g yarn@1.22.19

# install node-sass
npm install -g node-sass

# yes we need to install bz2 library
sudo apt-get install libbz2-dev -y

sudo apt install build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libsqlite3-dev libreadline-dev libffi-dev curl libbz2-dev -y

# then we have to update the path for our shell
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.profile
echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.profile
echo 'eval "$(pyenv init --path)"' >> ~/.profile

echo 'if command -v pyenv >/dev/null; then eval "$(pyenv init -)"; fi' >> ~/.bashrc
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
pyenv init --path

# make sure we have the right python, this should compile new python with bz2
pyenv install -v 3.14 -f

# now set the new python as global
pyenv global 3.14

pip install frappe-bench

frappe_prepare_bench 16 "/home/frappe/.pyenv/shims/python" || return 1
frappe_configure_bench || return 1
