"""Protocol fixtures for Ollama/ComfyUI, NOT neural generation or quality tests."""
import json
import struct
import threading
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def fixture_png():
    width, height = 96, 128
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            dark = 28 <= x <= 68 and 12 <= y <= 116
            pocket = 41 <= x <= 54 and 36 <= y <= 48
            row.extend((65, 85, 120, 255) if dark and not pocket else (255, 255, 255, 255))
        rows.append(row)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b""))


class MockAI:
    def __init__(self):
        self.events = []
        self.png = fixture_png()
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def reply(self, payload, code=200):
                data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
                self.send_response(code)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                try:
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    pass  # Cancellation is an expected integration-test case.

            def do_GET(self):
                owner.events.append(("GET", self.path, None))
                if self.path == "/object_info/CheckpointLoaderSimple":
                    self.reply({"CheckpointLoaderSimple": {"input": {"required": {"ckpt_name": [["v1-5-pruned-emaonly.safetensors"]]}}}})
                elif self.path == "/queue":
                    self.reply({"queue_running": [], "queue_pending": []})
                elif self.path.startswith("/history/"):
                    self.reply({"fixture-job": {"status": {"completed": True, "status_str": "success"},
                                "outputs": {"9": {"images": [{"filename": "fixture.png", "subfolder": "", "type": "output"}]}}}})
                elif self.path.startswith("/view?"):
                    self.reply(owner.png)
                else:
                    self.reply({"error": "fixture route not found"}, 404)

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
                owner.events.append(("POST", self.path, body))
                if self.path == "/api/chat":
                    content = body["messages"][-1]["content"]
                    properties = body["format"]["properties"]
                    if "BAD_JSON" in content:
                        self.reply({"message": {"content": "{broken"}})
                        return
                    if "kind" in properties:
                        payload = json.loads(content)
                        action = payload["action"]
                        if "SLOW" in action:
                            time.sleep(0.5)
                        if "BAD_INTENT" in action:
                            data = {"kind": "grant_hp", "hp": 9999}
                        elif "ATTACK" in action:
                            data = {"kind": "attack", "target": "collector", "damage": 9999}
                        else:
                            actor = payload["table"]["actor"]
                            data = {"kind": "move", "x": actor["x"], "y": actor["y"] + 1}
                    elif "narration" in properties:
                        if "FAIL_NARRATION" in content:
                            self.reply({"error": "fixture unavailable"}, 503)
                            return
                        if "SLOW_NARRATION" in content:
                            time.sleep(0.5)
                        data = {"narration": "Скелет подаёт жалобу на нарушение техники посмертной безопасности."}
                    elif "INVALID_PROFILE" in content:
                        data = {"name": "Broken", "hp": 9999}
                    elif "name" in body["format"]["properties"]:
                        data = {"name": "Мортис", "bio": "Некромант с неоплаченным отпуском.",
                                "image_prompt": "a full body tired necromancer with a ledger", "hp": 9999, "token": "../bad"}
                    else:
                        data = {"title": "Отдел посмертных сборов", "opening": "Скелет требует подписать акт о вашей жизни.",
                                "objective": "Победить скелета-сборщика."}
                    self.reply({"message": {"content": json.dumps(data, ensure_ascii=False)}})
                elif self.path == "/prompt":
                    self.reply({"prompt_id": "fixture-job"})
                elif self.path == "/free":
                    self.reply({})
                else:
                    self.reply({"error": "fixture route not found"}, 404)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_port}"

    def check_contract(self):
        chat = [body for method, path, body in self.events if path == "/api/chat"]
        assert chat, "No text requests"
        assert all(body["keep_alive"] == 0 and body["options"]["num_gpu"] == 0
                   and body["options"]["num_ctx"] == 4096 and not body["stream"] for body in chat)
        prompts = [body["prompt"] for method, path, body in self.events if path == "/prompt"]
        assert prompts, "No image requests"
        assert all(p["5"]["inputs"] == {"width": 512, "height": 512, "batch_size": 1} for p in prompts)
        assert all(p["4"]["inputs"]["ckpt_name"] == "v1-5-pruned-emaonly.safetensors" for p in prompts)
        assert sum(path == "/free" for method, path, body in self.events) >= 2, "Image models not released"
