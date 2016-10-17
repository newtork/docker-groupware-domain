FROM newtork/groupware-domain-stub:latest

MAINTAINER newtork / Alexander Dümont <alexander_duemont@web.de>


##########################################
#                                        #
#    Docker Build                        #
#                                        #
##########################################

#
# USAGE
# -----
#   docker pull newtork/groupware-domain
#   docker build -t newtork/groupware-domain .
#
#	See README for run command.
#

##########################################
#                                        #
#    Arguments                           #
#                                        #
##########################################

ARG LISTEN_IP
ENV LISTEN_IP ${LISTEN_IP:-127.0.0.1}

ARG DOMAIN_PATH
ENV DOMAIN_PATH ${DOMAIN_PATH:-/data/ad01}

ARG DOMAIN_NAME
ENV DOMAIN_NAME ${DOMAIN_NAME:-MY}

ARG DOMAIN_FQN
ENV DOMAIN_FQN ${DOMAIN_FQN:-MY.EXAMPLE.COM}

ARG DOMAIN_ADMINPASSWORD
ENV DOMAIN_ADMINPASSWORD ${DOMAIN_ADMINPASSWORD:-Passw0rd}

ARG LISTEN_INTERFACE
ENV LISTEN_INTERFACE ${LISTEN_INTERFACE:-eth0}



##########################################
#                                        #
#    Build Settings / Environment        #
#                                        #
##########################################

#### Port Usage for samba active directory
#
#	Service					Port		Protocol
#	--------------------	--------	--------
#	DNS						53			tcp/udp
#	Kerberos				88			tcp/udp
#	End Point Mapper		135			tcp
#	NetBIOS Name Service	137			udp
#	NetBIOS Datagram		138			udp
#	NetBIOS Session			139			tcp
#	LDAP					389			tcp/udp
#	SMB over TCP			445			tcp
#	Kerberos kpasswd		464			tcp/udp
#	LDAPS					636			tcp
#	Dynamic RPC Ports		1024-5000	tcp
#	Global Cataloge			3268		tcp
#	Global Cataloge SSL		3269		tcp

EXPOSE 53 88 135 137 138 139 389 445 464 636 1024-1152 3268 3269



# just start in root
WORKDIR /root/

COPY domain-controller.sh /root/



##########################################
#                                        #
#    PREPARATION                         #
#                                        #
##########################################

#
#   Build-Process:
#   --------------
#
#   1)  Just download and install required packages.
#
#


RUN chmod +x /root/domain-controller.sh


###############################################
#                                             #
#    START                                    #
#                                             #
###############################################

# Use the server wrapper file, no default CMD / arguments
ENTRYPOINT /root/domain-controller.sh \
			-d $DOMAIN_PATH \
			-s $DOMAIN_NAME \
			-n $DOMAIN_FQN \
			-p $DOMAIN_ADMINPASSWORD \
			-e $LISTEN_INTERFACE \
			-l $LISTEN_IP
			