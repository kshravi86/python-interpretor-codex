import os, time, sys, json, urllib.request

try:
    import jwt  # PyJWT
except Exception as e:
    print(f"::warning title=ASC check::PyJWT not available: {e}")
    sys.exit(0)

API_KEY_ID = os.environ.get('APP_STORE_CONNECT_API_KEY_ID','')
ISSUER_ID = os.environ.get('APP_STORE_CONNECT_ISSUER_ID','')
P8 = os.environ.get('APP_STORE_CONNECT_API_PRIVATE_KEY','')
BUNDLE_ID = os.environ.get('BUNDLE_ID','')

if not (API_KEY_ID and ISSUER_ID and P8 and BUNDLE_ID):
    print("::warning title=ASC check::Missing API credentials or bundle id; skipping")
    sys.exit(0)

def token():
    return jwt.encode({'iss': ISSUER_ID, 'exp': int(time.time()) + 900, 'aud': 'appstoreconnect-v1'}, P8, algorithm='ES256', headers={'kid': API_KEY_ID})

def get(url):
    req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token()}', 'Accept':'application/json'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode('utf-8'))

def app_id_for_bundle(bundle_id):
    data = get(f"https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]={bundle_id}&limit=1")
    items = data.get('data', [])
    return items[0]['id'] if items else None

def list_builds(app_id, limit=5):
    data = get(f"https://api.appstoreconnect.apple.com/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit={limit}")
    return data.get('data', [])

app_id = app_id_for_bundle(BUNDLE_ID)
if not app_id:
    print(f"::warning title=ASC check::App not found for bundle {BUNDLE_ID}")
    sys.exit(0)

def attr(b, k):
    return b.get('attributes', {}).get(k)

deadline = time.time() + 300  # poll up to 5 minutes
last_summary = None
while True:
    builds = list_builds(app_id)
    if builds:
        summary = []
        for b in builds:
            v = attr(b,'version'); bn = attr(b,'buildVersion'); st = attr(b,'processingState'); up = attr(b,'uploadedDate')
            summary.append(f"{v} ({bn}) state={st} uploaded={up}")
        joined = " | ".join(summary)
        if joined != last_summary:
            print("::notice title=ASC builds::" + joined)
            last_summary = joined
        states = {attr(b,'processingState') for b in builds}
        if 'VALID' in states:
            print("::notice title=ASC check::Build is VALID and should appear in TestFlight shortly")
            break
        if 'PROCESSING' in states:
            if time.time() >= deadline:
                print("::notice title=ASC check::Build still PROCESSING; will appear after Apple finishes")
                break
        else:
            print("::notice title=ASC check::Build states: " + ", ".join(states))
            break
    else:
        print("::notice title=ASC check::No builds returned yet (processing queue)")
        if time.time() >= deadline:
            break
    time.sleep(30)

