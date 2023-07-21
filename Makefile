run:
	sh -c 'Xephyr -screen 1024x768 -ac :64 & \
		sleep 1 && \
		DISPLAY=:64 sh ./xinitrc :64'

runm:
	sh -c 'Xephyr +xinerama -screen 800x600 -screen 800x600 -ac :64 & \
		sleep 1 && \
		DISPLAY=:64 sh ./xinitrc :64'
