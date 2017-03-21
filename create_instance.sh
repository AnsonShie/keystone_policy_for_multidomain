#!/usr/bin/env bash

OPENSTACK_HOST=$1
CINDER_HOST=$2
KEYSTONE_URL=http://${OPENSTACK_HOST}:5000/v3
GLANCE_URL=http://${OPENSTACK_HOST}:9292/v2
CINDER_URL=http://${CINDER_HOST}:8776/v2
NEUTRON_URL=http://${OPENSTACK_HOST}:9696/v2.0
NOVA_URL=http://${OPENSTACK_HOST}:8774/v2
USER_NAME=$3
PASSWD=$4
DOMAIN_NAME=$5
PROJECT_NAME=$6
IMAGE_NAME=$7
VOLUME_TYPE=$8
EXTERNAL_NETWORK_NAME=$9

if [ "$PROJECT_NAME" == "" ]; then
        echo "usage: ./create_domain HOST_IP CINDER_HOST_IP USER_NAME PASSWORD DOMAIN_NAME PROJECT_NAME IMAGE_NAME VOLUME_TYPE EXTERNAL_NETWORK_NAME"
        echo "        HOST_IP: The IP of API"
        echo "        CINDER_HOST_IP: The IP of Cinder API"
        echo "        USER_NAME: The name of the user under the domain"
        echo "        PASSWORD: The user password"
        echo "        DOMAIN_NAME: The name of the domain"
        echo "        PROJECT_NAME: The name of the project under the domain"
        echo "        IMAGE_NAME: The name of the image for instance"
        echo "        VOLUME_TYPE: The type of the volume"
        echo "        EXTERNAL_NETWORK_NAME: The name of the external/public network"
        exit 1
fi

cat > login.json <<EOF
{
    "auth": {
        "identity": {
            "methods": ["password"],
            "password": {
                "user": {
                    "name": "${USER_NAME}",
                    "domain": {
                        "name": "${DOMAIN_NAME}"
                    },
                    "password":"${PASSWD}"
                }
            }
        },
        "scope": {
            "project": {
                "name": "${PROJECT_NAME}",
                "domain": {
                    "name": "${DOMAIN_NAME}"
                }
            }
        }
    }
}
EOF
echo "[INFO] Get project scoped auth token."
PROJECT_TOKEN=$(curl -i -d @login.json -H "Content-type: application/json" \
 ${KEYSTONE_URL}/auth/tokens | grep X-Subject-Token | grep X-Subject-Token | tail -c 34)

if [ "$PROJECT_TOKEN" == "" ]; then
        echo "[ERROR] Get project scoped auth token failed."
        exit 1
fi

curl -H "X-Auth-Token: ${PROJECT_TOKEN:0:32}" ${KEYSTONE_URL}/auth/projects > project.log.json

PROJECT_ID=$(cat project.log.json | python -c "import sys, json; print json.load(sys.stdin)['projects'][0]['id']")

curl -H "X-Auth-Token: ${PROJECT_TOKEN:0:32}" ${GLANCE_URL}/images?name=${IMAGE_NAME} > image.log.json

IMAGE_ID=$(cat image.log.json | python -c "import sys, json; print json.load(sys.stdin)['images'][0]['id']")

if [ "$IMAGE_ID" == "" ]; then
        echo "[ERROR] Get image ID failed."
        cat image.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Create root volume."
cat > volume.json <<EOF
{
    "volume": {
        "size": 10,
        "name": "boot-volume",
        "description":null,
        "imageRef": "${IMAGE_ID}",
        "volume_type": "${VOLUME_TYPE}"
    }
}
EOF
curl -X POST -d @volume.json -H "Content-type: application/json" \
-H "X-Auth-Token: ${PROJECT_TOKEN:0:32}" ${CINDER_URL}/${PROJECT_ID}/volumes > volume.log.json

CREATED_VOLUME_ID=$(cat volume.log.json | python -c "import sys, json; print json.load(sys.stdin)['volume']['id']")

if [ "$CREATE_VOLUME_ID" == "" ]; then
        echo "[ERROR] Create root volume failed."
        cat volume.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Create router."

curl  -H "X-Auth-Token: ${PROJECT_TOKEN:0:32}" ${NEUTRON_URL}/networks?name=${EXTERNAL_NETWORK_NAME} > exter_net.log.json

EXTERNAL_NETWORK_ID=$(cat exter_net.log.json | python -c "import sys, json; print json.load(sys.stdin)['networks'][0]['id']")

if [ "$EXTERNAL_NETWORK_ID" == "" ]; then
        echo "[ERROR] Can not find the ID of external/public network."
        cat exter_net.log.json | python -m json.tool
        exit 1
fi

cat > router.json <<EOF
{
    "router": {
        "name": "router1",
        "external_gateway_info": {
            "network_id": "${EXTERNAL_NETWORK_ID}"
        },
        "admin_state_up": true
    }
}
EOF
curl -X POST -d @router.json -H "Content-type: application/json" -H "X-Auth-Token: ${PROJECT_TOKEN:0:32}" ${NEUTRON_URL}/routers > router.log.json

ROUTER_ID=$(cat router.log.json | python -c "import sys, json; print json.load(sys.stdin)['router']['id']")

if [ "$ROUTER_ID" == "" ]; then
        echo "[ERROR] Create router failed."
        cat router.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Create network."

curl -X POST -d '{"network": {"name": "sample_network","admin_state_up": true}}' \
-H "Content-type: application/json" -H "X-Auth-Token: ${PROJECT_TOKEN:0:32}" ${NEUTRON_URL}/networks > network.log.json

CREATED_NETWORK_ID=$(cat network.log.json | python -c "import sys, json; print json.load(sys.stdin)['network']['id']")

if [ "$CREATED_NETWORK_ID" == "" ]; then
        echo "[ERROR] Create network failed."
        cat network.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Create subnet under the created network."

cat > subnet.json <<EOF
{
    "subnet": {
        "network_id": "${CREATED_NETWORK_ID}",
        "ip_version": 4,
        "cidr": "192.168.199.0/24",
        "gateway_ip": "192.168.199.254",
        "enable_dhcp": true
    }
}
EOF

curl -X POST -d @subnet.json -H "Content-type: application/json" \
-H "X-Auth-Token: ${PROJECT_TOKEN:0:32}" ${NEUTRON_URL}/subnets > subnet.log.json

CREATED_SUBNET_ID=$(cat subnet.log.json | python -c "import sys, json; print json.load(sys.stdin)['subnet']['id']")

if [ "$CREATED_SUBNET_ID" == "" ]; then
        echo "[ERROR] Create subnet under the created network failed."
        cat subnet.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Add the created subnet to the created router."

cat > subnet_to_router.json <<EOF
{
    "subnet_id": "${CREATED_SUBNET_ID}"
}
EOF

curl -X PUT -d @subnet_to_router.json -H "Content-type: application/json" \
-H "X-Auth-Token: ${PROJECT_TOKEN:0:32}" ${NEUTRON_URL}/routers/${ROUTER_ID}/add_router_interface > router.log.json

if [ "$(cat router.log.json | python -c "import sys, json; print json.load(sys.stdin)['subnet_id']")" != "$CREATED_SUBNET_ID" ]; then
        echo "[ERROR] Add the created subnet to the created router failed."
        cat router.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Create instance."

sleep 30

cat > instance.json <<EOF
{
    "server": {
        "name": "instance-01",
        "imageRef": "",
        "block_device_mapping": [
            {
                "volume_id": "${CREATED_VOLUME_ID}",
                "device_name": "vda"
            }
        ],
        "flavorRef": "1",
        "max_count": 1,
        "min_count": 1,
        "networks": [
            {
                "uuid": "${CREATED_NETWORK_ID}"
            }
        ]
    }
}
EOF

curl -X POST -H "Content-Type: application/json" -d @instance.json \
-H "X-Auth-Token: ${PROJECT_TOKEN:0:32}" ${NOVA_URL}/${PROJECT_ID}/os-volumes_boot > instance.log.json

INSTANCE_ID=$(cat instance.log.json | python -c "import sys, json; print json.load(sys.stdin)['server']['id']")

if [ "$INSTANCE_ID" == "" ]; then
        echo "[ERROR] Create instance failed."
        cat instance.log.json | python -m json.tool
        exit 1
fi

echo '[INFO] Sleep 30 sec for waiting vm created finished'
sleep 30

curl -H "X-Auth-Token: ${PROJECT_TOKEN:0:32}" ${NOVA_URL}/${PROJECT_ID}/servers/${INSTANCE_ID} | python -m json.tool