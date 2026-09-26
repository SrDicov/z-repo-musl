# z-repo-musl — Z Linux Binary Repository (musl)

Gemelo musl de `z-repo`: misma estructura y workflow, solo **`x86_64-musl`**
en contenedor `void-musl-full`, publicado como assets del release `stable`.

- **Repo XBPS:** `https://github.com/SrDicov/z-repo-musl/releases/download/stable`
- **Source repo (plantillas):** `https://github.com/SrDicov/z-packages` (`srcpkgs/`)
- **Llave pública:** `keys/zlinux-repo.pub` (misma llave que `z-repo`)

## Uso en mklive.sh
```bash
mkdir -p "$ROOTFS/var/db/xbps/keys"
curl -sL https://srdicov.github.io/z-repo/keys/zlinux-repo.pub -o "$ROOTFS/var/db/xbps/keys/zlinux-repo.pub"

sudo ./mklive.sh \
  -r https://github.com/SrDicov/z-repo-musl/releases/download/stable \
  -r https://repo-default.voidlinux.org/current/x86_64-musl \
  -t x86_64-musl-YYYYMMDD-labwc
```

## Workflow
Idéntico a `z-repo`: `check` compara templates con assets del release
(`check_outdated.py --arch=x86_64-musl`, respeta `broken=` bajo
`XBPS_TARGET_LIBC=musl`); `build` compila solo el gap, prune a la versión
más nueva por `pkgname`, firma y sube solo lo cambiado.

Disparadores: diario (`0 3 * * *`), `repository_dispatch`
(`z-packages-update`), manual con `packages=`, `sync_only=` o `force=`.

## Crear el repo en GitHub
```bash
cd /home/dicov/z-repo-musl
git init -b master && git add -A && git commit -m "feat: musl twin of z-repo"
gh repo create SrDicov/z-repo-musl --public --source=. --push
gh secret set XBPS_PRIVATE_KEY < /ruta/privkey.pem --repo SrDicov/z-repo-musl
gh release create stable --title "Z Linux musl repo" \
  --notes "Rolling XBPS repo for x86_64-musl." --repo SrDicov/z-repo-musl
```
