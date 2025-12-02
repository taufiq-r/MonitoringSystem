import os
import json
from flask import Flask, request, jsonify
import logging
import requests

app = Flask(__name__)

LOG_DIR = '/var/log/alerts'
LOG_FILE = os.path.join(LOG_DIR, 'alerts.log')

os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=LOG_FILE, level=logging.INFO,
                    format='%(asctime)s %(levelname)s %(message)s')

GITHUB_TOKEN = os.environ.get('GITHUB_TOKEN')
GITHUB_REPO = os.environ.get('GITHUB_REPO')  # owner/repo
DISCORD_WEBHOOK_URL = os.environ.get('DISCORD_WEBHOOK_URL')


@app.route('/', methods=['GET'])
def health():
    return jsonify({'status': 'ok', 'service': 'incident-webhook'})


@app.route('/alert', methods=['POST'])
def alert():
    payload = request.get_json()
    logging.info('Received alert: %s', json.dumps(payload))

    # If GitHub integration is configured, create an issue for critical alerts
    if GITHUB_TOKEN and GITHUB_REPO:
        try:
            alerts = payload.get('alerts', [])
            for a in alerts:
                labels = a.get('labels', {})
                severity = labels.get('severity', 'none')
                title = f"[{severity}] {labels.get('alertname', 'Alert')} on {labels.get('instance', '')}"
                body = '```\n' + json.dumps(a, indent=2) + '\n```'
                if severity == 'critical':
                    create_github_issue(title, body)
        except Exception as e:
            logging.exception('Error creating GitHub issue: %s', e)

    # If Discord webhook is configured, post a summary message
    if DISCORD_WEBHOOK_URL:
        try:
            send_to_discord(payload)
        except Exception as e:
            logging.exception('Error sending to Discord: %s', e)

    return jsonify({'status': 'ok'})


def create_github_issue(title, body):
    url = f'https://api.github.com/repos/{GITHUB_REPO}/issues'
    headers = {
        'Authorization': f'token {GITHUB_TOKEN}',
        'Accept': 'application/vnd.github.v3+json'
    }
    data = {'title': title, 'body': body}
    r = requests.post(url, headers=headers, json=data, timeout=10)
    if r.status_code in (200, 201):
        logging.info('Created GitHub issue: %s', r.json().get('html_url'))
    else:
        logging.error('Failed to create GitHub issue: %s %s', r.status_code, r.text)


def send_to_discord(payload):
    alerts = payload.get('alerts', [])
    if not alerts:
        return

    parts = []
    for a in alerts:
        labels = a.get('labels', {})
        annotations = a.get('annotations', {})
        status = a.get('status', '')
        startsAt = a.get('startsAt', '')
        endsAt = a.get('endsAt', '')
        part = f"**{labels.get('alertname','Alert')}**\n" \
               f"- Severity: {labels.get('severity','-')}\n" \
               f"- Instance: {labels.get('instance','-')}\n" \
               f"- Status: {status}\n" \
               f"- Starts: {startsAt}\n"
        if annotations.get('summary'):
            part += f"- Summary: {annotations.get('summary')}\n"
        if annotations.get('description'):
            part += f"- Description: {annotations.get('description')}\n"
        parts.append(part)

    content = "\n---\n".join(parts)

    data = {'content': content}
    headers = {'Content-Type': 'application/json'}
    r = requests.post(DISCORD_WEBHOOK_URL, headers=headers, json=data, timeout=10)
    if r.status_code in (200, 204):
        logging.info('Sent alert to Discord webhook')
    else:
        logging.error('Failed to send to Discord: %s %s', r.status_code, r.text)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
