# Nemo on the tooling server (port + nginx)

## Port

`sync-nemo-tooling.sh` publishes Nemo on the **host** using **`NEMO_HOST_PORT`** (default **5455**). The container still listens on **5053** inside the image (`-p ${NEMO_HOST_PORT}:5053`).

After changing the default or env, redeploy Nemo (e.g. run `spin-node.sh` without `--skip-nemo`, or invoke `sync-nemo-tooling.sh` manually) so Docker recreates the `nemo` container with the new publish port.

## nginx

1. Copy the example site and edit `server_name` (and SSL stanzas if you use HTTPS):

   ```sh
   sudo cp /path/to/lean-quickstart/tooling/nginx-nemo.conf.example /etc/nginx/sites-available/nemo
   sudoedit /etc/nginx/sites-available/nemo
   ```

2. Ensure the **`upstream`** `server` line matches **`NEMO_HOST_PORT`** (default `127.0.0.1:5455`).

3. Enable and reload:

   ```sh
   sudo ln -sf /etc/nginx/sites-available/nemo /etc/nginx/sites-enabled/
   sudo nginx -t && sudo systemctl reload nginx
   ```

If you previously proxied to port **5053**, update that line to **5455** (or whatever you set for `NEMO_HOST_PORT`).
