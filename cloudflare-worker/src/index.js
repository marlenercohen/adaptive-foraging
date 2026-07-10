const DEFAULT_MAX_BYTES = 25 * 1024 * 1024;

function corsHeaders(request, env) {
  const origin = request.headers.get('Origin') || '';
  const allowed = (env.ALLOWED_ORIGINS || 'https://marlenercohen.github.io')
    .split(',')
    .map(value => value.trim())
    .filter(Boolean);
  const allowOrigin = allowed.includes(origin) ? origin : allowed[0];
  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Methods': 'POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin'
  };
}

function jsonResponse(request, env, body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      ...corsHeaders(request, env)
    }
  });
}

function safeSegment(value) {
  return String(value || 'unknown').replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 160);
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders(request, env) });
    }
    if (request.method !== 'POST') {
      return jsonResponse(request, env, { error: 'Method not allowed.' }, 405);
    }

    const origin = request.headers.get('Origin') || '';
    const allowedOrigins = (env.ALLOWED_ORIGINS || 'https://marlenercohen.github.io')
      .split(',')
      .map(value => value.trim())
      .filter(Boolean);
    if (!allowedOrigins.includes(origin)) {
      return jsonResponse(request, env, { error: 'Origin not allowed.' }, 403);
    }

    const contentType = request.headers.get('Content-Type') || '';
    if (!contentType.toLowerCase().includes('application/json')) {
      return jsonResponse(request, env, { error: 'Content-Type must be application/json.' }, 415);
    }

    const contentLength = Number(request.headers.get('Content-Length') || 0);
    const maxBytes = Math.max(1024, Number(env.MAX_UPLOAD_BYTES) || DEFAULT_MAX_BYTES);
    if (contentLength > maxBytes) {
      return jsonResponse(request, env, { error: `Upload exceeds ${maxBytes} bytes.` }, 413);
    }

    let text;
    try {
      text = await request.text();
    } catch {
      return jsonResponse(request, env, { error: 'Could not read request body.' }, 400);
    }
    if (new TextEncoder().encode(text).byteLength > maxBytes) {
      return jsonResponse(request, env, { error: `Upload exceeds ${maxBytes} bytes.` }, 413);
    }

    let payload;
    try {
      payload = JSON.parse(text);
    } catch {
      return jsonResponse(request, env, { error: 'Request body is not valid JSON.' }, 400);
    }

    const sessionId = safeSegment(payload?.sessionId);
    if (!payload?.sessionId || !payload?.sessionData || payload?.sessionData?.schemaVersion !== '1.0.0') {
      return jsonResponse(request, env, { error: 'Missing or invalid session data.' }, 400);
    }

    const date = new Date();
    const datePath = `${date.getUTCFullYear()}/${String(date.getUTCMonth() + 1).padStart(2, '0')}/${String(date.getUTCDate()).padStart(2, '0')}`;
    const objectKey = `adaptive-foraging/${datePath}/${sessionId}.json`;

    await env.SESSION_BUCKET.put(objectKey, text, {
      httpMetadata: { contentType: 'application/json' },
      customMetadata: {
        sessionId,
        uploadedAt: safeSegment(payload?.uploadedAt),
        sourceOrigin: safeSegment(origin)
      }
    });

    return jsonResponse(request, env, {
      ok: true,
      sessionId,
      objectKey
    });
  }
};
