"""Fails if pubspec.yaml's version can no longer take new App Store builds.

Apple closes a version's "train" once that version is approved/released;
any further build uploaded under it is rejected with ITMS-90186 - but
only during asynchronous processing, after the upload itself has already
"succeeded". The deploy workflow doesn't wait for processing, so without
this check the pipeline goes green and the failure only arrives by mail.

Needs APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_ID and
APP_STORE_CONNECT_API_KEY (the .p8 contents) in the environment, plus
`pip install pyjwt cryptography`.
"""

import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

import jwt

BUNDLE_ID = 'net.webtrees.webtreesmobile'

# appVersionState values after which Apple no longer accepts builds for
# that version string.
CLOSED_STATES = {
    'ACCEPTED',
    'PENDING_APPLE_RELEASE',
    'PENDING_DEVELOPER_RELEASE',
    'PROCESSING_FOR_DISTRIBUTION',
    'READY_FOR_DISTRIBUTION',
    'REPLACED_WITH_NEW_VERSION',
}


def pubspec_version():
    with open('pubspec.yaml') as f:
        match = re.search(r'^version:\s*([0-9.]+)', f.read(), re.MULTILINE)
    return match.group(1)


def parse(version):
    return tuple(int(part) for part in version.split('.'))


def api_get(token, path, params):
    url = f'https://api.appstoreconnect.apple.com/v1/{path}?{urllib.parse.urlencode(params)}'
    request = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}'})
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def main():
    token = jwt.encode(
        {
            'iss': os.environ['APP_STORE_CONNECT_ISSUER_ID'],
            'exp': int(time.time()) + 600,
            'aud': 'appstoreconnect-v1',
        },
        os.environ['APP_STORE_CONNECT_API_KEY'],
        algorithm='ES256',
        headers={'kid': os.environ['APP_STORE_CONNECT_KEY_ID']},
    )

    apps = api_get(token, 'apps', {'filter[bundleId]': BUNDLE_ID})['data']
    if not apps:
        sys.exit(f'No App Store Connect app found for {BUNDLE_ID}')
    versions = api_get(
        token,
        f'apps/{apps[0]["id"]}/appStoreVersions',
        {'filter[platform]': 'IOS', 'limit': 200, 'fields[appStoreVersions]': 'versionString,appVersionState'},
    )['data']

    closed = [
        v['attributes']['versionString']
        for v in versions
        if v['attributes'].get('appVersionState') in CLOSED_STATES
    ]
    current = pubspec_version()
    if closed:
        highest = max(closed, key=parse)
        if parse(current) <= parse(highest):
            sys.exit(
                f'pubspec.yaml version {current} is not above the already released '
                f'iOS version {highest} - Apple would reject the build (ITMS-90186). '
                'Bump the version in pubspec.yaml.'
            )
    print(f'Version {current} is open for new builds.')


if __name__ == '__main__':
    main()
