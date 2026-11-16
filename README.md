# Cine deployment

This directory is the contents of the private deployment repository. It contains the production Docker Compose stack and the remote deployment/rollback script.

## Initial server setup

1. Install Docker Engine with the Docker Compose plugin on Ubuntu Server.
2. Put the files from this repository at `/opt/cine-deploy` on the VM and create the runtime files:

   ```sh
   cd /opt/cine-deploy
   cp .env.example .env
   cp versions.env.example versions.env
   chmod 600 .env versions.env
   ```

3. Edit `.env` on the server. Set a unique long `POSTGRES_PASSWORD` and `JWT_SECRET`; do not commit `.env`.
4. Ensure the account that will run the GitHub Actions self-hosted runner can run Docker Compose and access this directory. Do not expose SSH to the Internet for this local VirtualBox setup.

The backend and frontend workflows start their service and dependencies after publishing each image. Keep the VM running while workflows deploy.

With VirtualBox NAT, configure a VirtualBox port-forwarding rule from a host port (for example `8080`) to guest port `80` to open the frontend from the host at `http://localhost:8080`. Do not forward SSH to the public Internet.

The database and uploaded images are stored in named Docker volumes. PostgreSQL port 5432 is not published. The frontend image serves the SPA and reverse-proxies `/api/` and `/documentacion` to the backend.

## GitHub Actions self-hosted runners

Install a separate Linux x64 self-hosted runner from **Settings → Actions → Runners → New self-hosted runner** in each application repository. Register both runners with the default labels (`self-hosted`, `linux`, `x64`), install each runner as a service, and keep the Ubuntu VM running. Do not share the temporary registration tokens shown by GitHub.

The runner account needs Docker access and read/write access to `/opt/cine-deploy`. The application workflows build and publish images on GitHub-hosted runners, then the self-hosted runner pulls the commit-SHA image and executes the Compose deployment locally. No SSH key or VPS secrets are required in GitHub Actions.

Self-hosted runners execute workflow code on the VM. Keep these repositories under your control, do not run pull-request workflows from untrusted contributors on these runners, and keep deployments restricted to `main`.

## Rollback

After the first production release, each image workflow retains the previous production image under the Docker Hub tag `previous`. To restore it, set the relevant `BACKEND_TAG` or `FRONTEND_TAG` in `versions.env` to `previous`, then pull and restart the service:

```sh
docker compose --env-file .env --env-file versions.env -f compose.yaml pull api frontend
docker compose --env-file .env --env-file versions.env -f compose.yaml up -d --wait api frontend
```

`DB_SYNCHRONIZE=true` is required for this academic project because it currently has no TypeORM migrations. For a production system, create and apply migrations before changing this setting to `false`.
