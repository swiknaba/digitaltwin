"""Offline contract checks and read-only probe helpers, not Kirei routing code.

Source shapes: Mattermost v11.11.1 API4 post/channel/user handlers and model.
These checks cannot establish transport authentication or runtime permissions.
"""
import json
import re
from urllib.parse import urlencode


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r'[a-z0-9]{26}', value):
        raise ValueError('invalid Mattermost identifier')
    return value


def event_key(post, kind='posted'):
    if kind not in ('posted', 'post_edited', 'post_deleted'):
        raise ValueError('unsupported post event')
    for field in ('create_at', 'update_at', 'delete_at'):
        if type(post.get(field)) is not int or post[field] < 0:
            raise ValueError('missing or invalid revision timestamp')
    revision = max(post['create_at'], post['update_at'], post['delete_at'])
    return (identifier(post['channel_id']), identifier(post['id']), kind, revision)


def verify_post(post, root, member, user, channel_id, local_bot_ids=()):
    identifier(channel_id)
    event_key(post)
    event_key(root)
    sender = identifier(post['user_id'])
    thread = identifier(post.get('root_id') or post['id'])
    if post['channel_id'] != channel_id or root['channel_id'] != channel_id:
        raise ValueError('channel mismatch')
    if root['id'] != thread or root.get('root_id'):
        raise ValueError('thread target is not the root')
    if post['delete_at'] or root['delete_at']:
        raise ValueError('deleted post or root')
    if member.get('channel_id') != channel_id or member.get('user_id') != sender:
        raise ValueError('sender membership mismatch')
    # Release model/user.go uses omitempty for false IsBot. This argument
    # must be the authenticated REST user response, never an event claim.
    if user.get('id') != sender or type(user.get('is_bot', False)) is not bool:
        raise ValueError('sender identity or bot state is unverified')
    if sender in local_bot_ids:
        raise ValueError('local bot loop')
    return {'channel_id': channel_id, 'post_id': post['id'], 'thread_id': thread,
            'user_id': sender, 'bot': user.get('is_bot', False), 'revision': event_key(post)[3]}


def event_post(event):
    if event.get('event') not in ('posted', 'post_edited', 'post_deleted'):
        raise ValueError('unsupported event')
    if not isinstance(event.get('data', {}).get('post'), str):
        raise ValueError('event post must be a JSON string')
    post = json.loads(event['data']['post'])
    event_key(post, event['event'])
    broadcast_channel = event.get('broadcast', {}).get('channel_id')
    if broadcast_channel and broadcast_channel != post['channel_id']:
        raise ValueError('broadcast channel mismatch')
    return post


def history_posts(post_list, channel_id):
    identifier(channel_id)
    posts = post_list['posts']
    for key, post in posts.items():
        if key != post['id'] or post['channel_id'] != channel_id:
            raise ValueError('post map identity/channel mismatch')
        event_key(post)
    if any(key not in posts for key in post_list['order']):
        raise ValueError('order refers to an absent post')
    return sorted(posts.values(), key=lambda p: (event_key(p)[3], p['id']))


def backfill_path(channel_id, checkpoint_ms, overlap_ms=1000):
    identifier(channel_id)
    if type(checkpoint_ms) is not int or checkpoint_ms < 0 or overlap_ms < 0:
        raise ValueError('invalid millisecond checkpoint')
    # since=0 selects the paginated path in upstream; caller must paginate it.
    return '/api/v4/channels/' + channel_id + '/posts?' + urlencode({
        'since': max(0, checkpoint_ms - overlap_ms), 'collapsedThreads': 'false'})
