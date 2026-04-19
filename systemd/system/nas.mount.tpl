[Unit]
Description=Montage SSHFS NAS
After=network-online.target
Wants=network-online.target

[Mount]
Where=@MOUNT_PATH@
What=@NAS_USER@@@NAS_HOST@:@NAS_REMOTE_PATH@
Type=fuse.sshfs
Options=IdentityFile=@SSH_KEY@,StrictHostKeyChecking=accept-new,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,idmap=user,uid=@USER_UID@,gid=@USER_GID@,allow_other,default_permissions
LazyUnmount=yes

[Install]
WantedBy=multi-user.target