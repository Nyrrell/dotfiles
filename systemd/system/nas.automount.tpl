[Unit]
Description=Automount NAS (on-demand)

[Automount]
Where=@MOUNT_PATH@
TimeoutIdleSec=300

[Install]
WantedBy=multi-user.target