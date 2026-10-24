"""Fails if App Store Connect still has a version in review or waiting for release.

As long as one is, Apple takes no new version - and fastlane deliver then
renames that version to the new number instead (it did so with 1.6.0 ->
1.7.0, which kept the 1.6.0 build). Run before uploading for version <x.y.z>:

    python tool/check_app_store_editable.py 1.7.0

Same environment as check_ios_version_train.py.
"""

import os
import sys
import time

import jwt

from check_ios_version_train import BUNDLE_ID, api_get

# Submitted or approved but not yet live: no new version possible next to it.
IN_FLIGHT_STATES = {
    'WAITING_FOR_EXPORT_COMPLIANCE',
    'READY_FOR_REVIEW',
    'WAITING_FOR_REVIEW',
    'IN_REVIEW',
    'ACCEPTED',
    'PENDING_APPLE_RELEASE',
    'PENDING_DEVELOPER_RELEASE',
    'PROCESSING_FOR_DISTRIBUTION',
}


def main():
    version = sys.argv[1]
    token = jwt.encode(
        {'iss': os.environ['APP_STORE_CONNECT_ISSUER_ID'], 'exp': int(time.time()) + 600, 'aud': 'appstoreconnect-v1'},
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
    for v in versions:
        state = v['attributes'].get('appVersionState')
        if state in IN_FLIGHT_STATES:
            sys.exit(
                f'App Store version {v["attributes"]["versionString"]} is {state} - no new version {version} '
                'possible next to it. Wait until it is live, or remove it from review in App Store Connect, '
                'then run the Store workflow again (manually, with the tag).'
            )
    print(f'No version in review - {version} can be uploaded.')


if __name__ == '__main__':
    main()
