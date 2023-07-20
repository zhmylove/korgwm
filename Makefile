run:
	xinit ./xinitrc -- /usr/bin/Xephyr -host-cursor -screen 1024x768 -ac :64

runm:
	sh -c 'Xephyr +xinerama -screen 800x600 -screen 800x600 -ac :64 & \
		DISPLAY=:64 ./xinitrc :64'
