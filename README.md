
# Usage

To have the domain controller accessible from outside of Docker, consider setting the ports and your host IP as `LISTEN_IP`, e.g. *192.168.0.2*.


	docker run \
	  --cap-add SYS_ADMIN \
	  --hostname=dc01 \
	  --name=dc01 \
	  --volume /data:/data \
	  --rm \
	  -e "LISTEN_IP=192.168.0.2" \
	  -e "DOMAIN_PATH=/data/ad01" \
	  -e "DOMAIN_NAME=MY" \
	  -e "DOMAIN_FQN=MY.DOMAIN.EXAMPLE.COM" \
	  -e "DOMAIN_INTERFACE=eth0" \
	  -e "DOMAIN_ADMINPASSWORD=P4Ssw0Rd" \
	  -it \
	  -p 53:53 -p 53:53/udp \
	  -p 88:88 -p 88:88/udp \
	  -p 135:135 \
	  -p 137:137/udp \
	  -p 138:138/udp \
	  -p 139:139 \
	  -p 389:389 -p 389:389/udp \
	  -p 445:445 \
	  -p 464:464 -p 464:464/udp \
	  -p 636:636 \
	  -p 1024-1152:1024-1152 \
	  -p 3268:3268 \
	  -p 3269:3269 \
	  -p 22137:22137 \
	  newtork/groupware-domain


Please see [my blog](http://blog.newtork.de/tag/domain/) for more information.
