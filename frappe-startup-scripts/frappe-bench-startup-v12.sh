#!/usr/bin/env bash

# shellcheck source=frappe-bench-startup-common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/frappe-bench-startup-common.sh"
frappe_validate_ports || return 1

sudo chown frappe:frappe ../workspace

echo "alias ll='ls -al'" >> ~/.bashrc
alias ll='ls -al'

sudo apt update

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.2/install.sh | bash

export NVM_DIR="$HOME/.nvm"
frappe_load_nvm || return 1

echo "installing v14"
nvm deactivate && nvm uninstall 16 && nvm install 14 && nvm use 14 && nvm alias default 14 && nvm alias default node || return 1
frappe_resolve_node || return 1

npm install -g yarn

# install node-sass
npm install -g node-sass

# yes we need to install bz2 library
sudo apt-get install libbz2-dev -y

# then we have to update the path for our shell
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.profile
echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.profile
echo 'eval "$(pyenv init --path)"' >> ~/.profile

echo 'if command -v pyenv >/dev/null; then eval "$(pyenv init -)"; fi' >> ~/.bashrc
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
pyenv init --path

# make sure we have the right python, this should compile new python with bz2
pyenv install -v 3.7.12 -f
pyenv install -v 2.7.18 -f

# now set the new python as global
pyenv global 3.7.12 2.7.18

pip install frappe-bench

# sometimes bench won't work since it's not linking to bin/bench
# rm /home/frappe/.local/bin/bench
# ln /home/frappe/.pyenv/shims/bench /home/frappe/.local/bin/bench

pip install markupsafe==2.0.1

frappe_prepare_bench 12 "/home/frappe/.pyenv/shims/python" || return 1
frappe_configure_bench || return 1
