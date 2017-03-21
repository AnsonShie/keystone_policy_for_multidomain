#!/usr/bin/env bash

OPENSTACK_HOST=$1
KEYSTONE_URL=http://${OPENSTACK_HOST}:5000/v3
USER_NAME=$2
PASSWD=$3
DOMAIN_NAME=$4
USER_ROLE=$5

if [ "$USER_ROLE" == "" ]; then
        echo "usage: ./create_domain HOST_IP ADMIN_USER_NAME PASSWORD NEW_DOMAIN_NAME USER_ROLE"
        echo "        HOST_IP: The IP of API"
        echo "        ADMIN_USER_NAME: The admin user name of the domain"
        echo "        PASSWORD: The admin user password"
        echo "        NEW_DOMAIN_NAME: The name of the domain"
        echo "        USER_ROLE: The role name for end user"
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
            "domain": {
                "name": "${DOMAIN_NAME}"
            }
        }
    }
}
EOF
echo "[INFO] Get domain scoped auth token."
DOMAIN_TOKEN=$(curl -i -d @login.json -H "Content-type: application/json" \
 ${KEYSTONE_URL}/auth/tokens | grep X-Subject-Token | grep X-Subject-Token | tail -c 34)

if [ "$DOMAIN_TOKEN" == "" ]; then
        echo "[ERROR] Get domain scoped auth token failed."
        exit 1
fi

curl -H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" ${KEYSTONE_URL}/auth/domains > domain.log.json

YOUR_DOMAIN_ID=$(cat domain.log.json | python -c "import sys, json; print json.load(sys.stdin)['domains'][0]['id']")

echo "[INFO] Create new project under the domain."
cat > project.json <<EOF
{
    "project": {
        "description": "Demo project",
        "enabled": true,
        "name": "Demo_project",
        "domain_id":"${YOUR_DOMAIN_ID}"
    }
}
EOF

curl -X POST -d @project.json \
-H "Content-type: application/json" -H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" ${KEYSTONE_URL}/projects > project.log.json

PROJECT_ID=$(cat project.log.json | python -c "import sys, json; print json.load(sys.stdin)['project']['id']")

if [ "$PROJECT_ID" == "" ]; then
        echo "[ERROR] Create new project under the domain failed."
        cat project.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Create new user under the domain."
cat > user.json <<EOF
{
    "user": {
        "domain_id": "${YOUR_DOMAIN_ID}",
        "enabled": true,
        "name": "demo",
        "password": "foxconn"
    }
}
EOF

curl -X POST -d @user.json \
-H "Content-type: application/json" -H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" ${KEYSTONE_URL}/users > user.log.json

USER_ID=$(cat user.log.json | python -c "import sys, json; print json.load(sys.stdin)['user']['id']")

if [ "$USER_ID" == "" ]; then
        echo "[ERROR] Create new user under the domain failed."
        cat user.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Get end user role ID."

curl -H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" ${KEYSTONE_URL}/roles?name=${USER_ROLE} > user_role.log.json

USER_ROLE_ID=$(cat user_role.log.json | python -c "import sys, json; print json.load(sys.stdin)['roles'][0]['id']")

if [ "$USER_ROLE_ID" == "" ]; then
        echo "[ERROR] Get end user role ID failed."
        cat user_role.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Add user to project as role for end user."
curl -X PUT -H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" \
${KEYSTONE_URL}/projects/${PROJECT_ID}/users/${USER_ID}/roles/${USER_ROLE_ID} > user_to_project.log.json

USER_TO_PROJECT_ROLE=$(curl -H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" ${KEYSTONE_URL}/projects/${PROJECT_ID}/users/${USER_ID}/roles | \
python -c "import sys, json; print json.load(sys.stdin)['roles'][0]['id']")

if [ "$USER_ROLE_ID" != "$USER_TO_PROJECT_ROLE" ]; then
        echo "[ERROR] Add user to project as role:domain_admin failed."
        cat user_to_project.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Test: create user and project under the domain using domain_admin user auth key success"

