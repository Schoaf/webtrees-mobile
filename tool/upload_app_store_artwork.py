"""Uploads the product page artwork of App Store version <x.y.z>: the header
(21:9) and the search results image (3:2) of each store language, from
compose_store_banner.py. fastlane deliver doesn't know these yet (App Store,
iOS 27), so this goes through the App Asset Library of the App Store Connect
API:

    python tool/upload_app_store_artwork.py 1.11.0

Run after deliver uploaded the version's texts, before it is submitted:
placements can't be changed while the version is in review. Same environment
as check_ios_version_train.py.
"""

import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

import jwt

from check_ios_version_train import BUNDLE_ID, api_get

STORE_DIR = pathlib.Path(__file__).resolve().parent.parent / 'screenshots' / 'store'
# App Store locale -> language of compose_store_banner.py
LOCALES = {'de-DE': 'de', 'en-GB': 'en', 'nl-NL': 'nl'}
PLACEMENTS = {
    'PRODUCT_PAGE_HEADER_ASSET': '3840x1646',
    'APP_STORE_SEARCH_RESULTS_ASSET': '3840x2560',
}


def token():
    return jwt.encode(
        {'iss': os.environ['APP_STORE_CONNECT_ISSUER_ID'], 'exp': int(time.time()) + 1200, 'aud': 'appstoreconnect-v1'},
        os.environ['APP_STORE_CONNECT_API_KEY'],
        algorithm='ES256',
        headers={'kid': os.environ['APP_STORE_CONNECT_KEY_ID']},
    )


def api(tok, method, path, body=None):
    request = urllib.request.Request(
        f'https://api.appstoreconnect.apple.com/v1/{path}',
        data=None if body is None else json.dumps(body).encode(),
        method=method,
        headers={'Authorization': f'Bearer {tok}', 'Content-Type': 'application/json'},
    )
    try:
        with urllib.request.urlopen(request) as response:
            text = response.read()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        sys.exit(f'{method} {path}: {e.code} {e.read().decode(errors="replace")}')


def upload_image(tok, library_id, path):
    """Reserves, uploads and commits one image; returns its id once processed."""
    data = path.read_bytes()
    image = api(tok, 'POST', 'appAssetLibraryImages', {'data': {
        'type': 'appAssetLibraryImages',
        'attributes': {'category': 'CREATIVE_ASSETS', 'fileName': path.name, 'fileSize': len(data)},
        'relationships': {'assetLibrary': {'data': {'type': 'appAssetLibraries', 'id': library_id}}},
    }})['data']
    for operation in image['attributes']['uploadOperations']:
        part = data[operation['offset']:operation['offset'] + operation['length']]
        # The upload URLs are pre-signed: only their own headers, no token.
        headers = {h['name']: h['value'] for h in operation.get('requestHeaders', [])}
        urllib.request.urlopen(urllib.request.Request(operation['url'], data=part, method=operation['method'], headers=headers))
    api(tok, 'PATCH', f'appAssetLibraryImages/{image["id"]}', {'data': {
        'type': 'appAssetLibraryImages', 'id': image['id'], 'attributes': {'uploaded': True},
    }})
    for _ in range(60):
        state = api(tok, 'GET', f'appAssetLibraryImages/{image["id"]}')['data']['attributes'].get('state')
        if state not in ('AWAITING_UPLOAD', 'UPLOAD_COMPLETE'):
            break
        time.sleep(5)
    if state in ('FAILED', 'REJECTED'):
        sys.exit(f'{path.name}: Apple refused the image ({state})')
    return image['id']


def main():
    version = sys.argv[1]
    tok = token()
    app_id = api_get(tok, 'apps', {'filter[bundleId]': BUNDLE_ID})['data'][0]['id']
    library_id = api(tok, 'GET', f'apps/{app_id}/assetLibrary')['data']['id']
    versions = api_get(tok, f'apps/{app_id}/appStoreVersions',
                       {'filter[platform]': 'IOS', 'filter[versionString]': version})['data']
    if not versions:
        sys.exit(f'No App Store version {version} - run deliver first')
    localizations = api(tok, 'GET', f'appStoreVersions/{versions[0]["id"]}/appStoreVersionLocalizations')['data']

    for localization in localizations:
        lang = LOCALES.get(localization['attributes']['locale'])
        if lang is None:
            continue
        existing = api(tok, 'GET', f'appStoreVersionLocalizations/{localization["id"]}/placements')['data']
        for placement_type, size in PLACEMENTS.items():
            path = STORE_DIR / lang / 'banner' / f'{lang}_banner_{size}.png'
            image_id = upload_image(tok, library_id, path)
            # Placements can't be changed - replace the old one of this type.
            for old in existing:
                if old['attributes'].get('placementType') == placement_type:
                    api(tok, 'DELETE', f'appAssetLibraryPlacements/{old["id"]}')
            api(tok, 'POST', 'appAssetLibraryPlacements', {'data': {
                'type': 'appAssetLibraryPlacements',
                'attributes': {'placementType': placement_type},
                'relationships': {
                    'appStoreVersionLocalization': {'data': {'type': 'appStoreVersionLocalizations', 'id': localization['id']}},
                    'image': {'data': {'type': 'appAssetLibraryImages', 'id': image_id}},
                },
            }})
            print(f'{localization["attributes"]["locale"]}: {placement_type} <- {path.name}')


if __name__ == '__main__':
    main()
