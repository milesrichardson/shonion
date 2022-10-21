#!/usr/bin/env bash

build_dir="$(mktemp -d)"

pushd "$build_dir" \
  && touch sshd.pid \
  && ssh-keygen -f id_shonion_client_rsa -N '' \
  && cat id_shonion_client_rsa.pub > authorized_keys \
  && ssh-keygen -f ssh_host_rsa_key -N ''


cat <<EOC > "$build_dir/client_script.sh"
#!/usr/bin/env bash

cd \$(mktemp -d)

tee id_shonion_client_rsa <<EOX
$(cat id_shonion_client_rsa)
EOX

tee id_shonion_client_rsa.pub <<EOX
$(cat id_shonion_client_rsa.pub)
EOX

chmod 0400 id_shonion_client_rsa id_shonion_client_rsa.pub

exec ssh -v \\
    -F /dev/null \\
    -o IdentityFile=\$PWD/id_shonion_client_rsa \\
    -o IdentitiesOnly=yes \\
    -o ConnectTimeout=120 \\
    -o StrictHostKeychecking=no \\
    -o UserKnownHostsFile=/dev/null \\
    -o "proxyCommand=nc -x 127.0.0.1:19050 -X 5 %h %p" \\
$(whoami)@$(cat /tmp/tor-rust/hs-dir/hostname) -p 34567
EOC

echo "Listening..."
echo "To connect from another machine, paste this into a terminal:"
tee <<EOC
bash <(echo "$(base64 -w0 "$build_dir"/client_script.sh)" | base64 -D)
EOC

exec /usr/sbin/sshd -D \
-o Port=5678 \
-o StrictModes=no \
-o HostKey="$PWD"/ssh_host_rsa_key \
-o PidFile="$PWD"/sshd.pid \
-o KbdInteractiveAuthentication=no \
-o ChallengeResponseAuthentication=no \
-o PasswordAuthentication=no \
-o UsePAM=yes \
-o AuthorizedKeysFile="$PWD"/authorized_keys
