
# Usage


	docker run \
	  --cap-add SYS_ADMIN \
	  --hostname=dc01 \
	  --name=dc01 \
	  --net adnet \
	  --ip 172.42.0.2 \
	  --volume /data:/data \
	  --rm \
	  -e "LISTEN_IP=192.168.84.2" \
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
	  -p 3268 \
	  -p 3269 \
	  newtork/groupware-domain

