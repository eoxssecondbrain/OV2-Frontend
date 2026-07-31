"""Bridge: exposes an SSE-only MCP server over streamable HTTP.

Open WebUI speaks streamable HTTP only; the EOXS vault server speaks the
legacy HTTP+SSE transport. This opens a fresh upstream SSE session per
request, so there is no long-lived connection to go stale.

Temporary. Delete once the vault server serves streamable HTTP natively.
"""

import contextlib
import os

import anyio
import uvicorn
from mcp import ClientSession
from mcp.client.sse import sse_client
from mcp.server.lowlevel import Server
from mcp.server.streamable_http_manager import StreamableHTTPSessionManager
from starlette.applications import Starlette
from starlette.routing import Mount

UPSTREAM = os.environ["VAULT_MCP_URL"]
PORT = int(os.environ.get("VAULT_BRIDGE_PORT", "9090"))

server = Server("eoxs-vault-bridge")


@contextlib.asynccontextmanager
async def upstream():
    """One short-lived upstream session per call."""
    async with sse_client(UPSTREAM, timeout=30, sse_read_timeout=300) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            yield session


@server.list_tools()
async def list_tools():
    async with upstream() as session:
        tools = (await session.list_tools()).tools
        # Drop outputSchema: we relay the upstream payload verbatim, and the
        # local server would otherwise reject it for lacking structured output.
        for tool in tools:
            tool.outputSchema = None
        return tools


@server.call_tool()
async def call_tool(name: str, arguments: dict):
    async with upstream() as session:
        result = await session.call_tool(name, arguments)
        if result.isError:
            text = " ".join(getattr(c, "text", "") for c in result.content).strip()
            raise Exception(text or f"upstream tool {name} failed")
        if result.structuredContent is not None:
            return result.content, result.structuredContent
        return result.content


session_manager = StreamableHTTPSessionManager(app=server, json_response=True)


async def handle_mcp(scope, receive, send):
    await session_manager.handle_request(scope, receive, send)


@contextlib.asynccontextmanager
async def lifespan(app):
    async with session_manager.run():
        print(f"bridge ready on :{PORT}/mcp -> {UPSTREAM.split('/')[2]}", flush=True)
        yield


app = Starlette(routes=[Mount("/mcp", app=handle_mcp)], lifespan=lifespan)

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=PORT, log_level="warning")
