sudo systemctl stop nix-daemon.service
sudo systemctl disable nix-daemon.socket nix-daemon.service
sudo systemctl daemon-reload

sudo rm -rf /etc/nix /etc/profile.d/nix.sh /etc/tmpfiles.d/nix-daemon.conf /nix ~root/.nix-channels ~root/.nix-defexpr ~root/.nix-profile ~/.cache

for i in $(seq 1 32); do
	  sudo userdel "nixbld$i"
done
sudo groupdel nixbld

sh <(curl -L https://nixos.org/nix/install) --daemon
