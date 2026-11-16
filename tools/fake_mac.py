"""A pretend FU Mail desktop, for trying the app without real mail: `make fake-mac`.

Serves two conversations built from core/src/test/resources/fixtures: one with a list, a thread of
three, Add to note, CRM, events, a suggested note and a draft; the other with note cards (/obsidian)
and a CRM card that starts at its preview; and a third with the task cards (tasks, a new task, a change) on http://127.0.0.1:8799. In the emulator
the address is http://10.0.2.2:8799 and the token is fum_smoke. Buttons answer 202 and change
nothing; events are only pings. Python 3, standard library only.
"""
import datetime, json, os, sys, threading, time, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# --editor: start with a reply's draft editor open for the device (closed again by Cancel or Save).
EDITOR = "--editor" in sys.argv
# --port N: another port.
PORT = int(sys.argv[sys.argv.index("--port") + 1]) if "--port" in sys.argv else 8799
ARGS = [a for i, a in enumerate(sys.argv[1:], 1) if not a.startswith("--") and sys.argv[i - 1] != "--port"]
FIX = ARGS[0] if ARGS else os.path.join(os.path.dirname(__file__), "..", "FUMailKit", "Tests", "FUMailKitTests", "Fixtures")
TOKEN = "fum_smoke"
C1 = "5A277C52-1D0B-4A43-9C9E-2D5B8F1E0A00"
def fx(name): return open(f"{FIX}/{name}").read()

def msg(i, role, text="", card=None, at="2026-11-13T08:00:00Z"):
    m = {"id": f"5A277C52-0000-4000-8000-{i:012d}", "role": role, "text": text, "createdAt": at}
    if card is not None: m["card"] = card
    return m

thread = json.loads(fx("thread-message.json"))["card"]
t = thread["thread"]["_0"]
base = t["messages"][0]
older = dict(base, id="18c29", received="2026-11-05T10:00:00Z", body="Can you approve the Q4 numbers by Friday?", unread=False, attachments=[])
mine = dict(base, id="18c2b", received="2026-11-07T09:00:00Z", body="Looking at it today.", unread=False, attachments=[],
            **{"from": {"name": "Me", "email": "me@example.com"}, "to": [{"name": "Bob", "email": "bob@example.com"}],
               "cc": [{"name": "Carol", "email": "carol@example.com"}]})
base["cc"] = [{"name": "Carol", "email": "carol@example.com"}]
t["messages"] = [older, base, mine]
others = json.loads(fx("other-cards.json"))
crm = json.loads(fx("crm-card.json"))
note_view, note_choices, crm_preview = json.loads(fx("note-view.json"))
archive_list = json.loads(fx("archive.json"))
archived_thread = json.loads(json.dumps(thread))
archived_thread["thread"]["_0"].update(archived=True, subject="Renewal 2025")
note_view["noteView"]["_0"].pop("only")  # all three sections
messages = [
    msg(1, "user", "/unread"),
    msg(2, "assistant", "", json.loads(fx("list-card.json"))),
    msg(3, "user", "/open 1"),
    msg(4, "assistant", "", thread),
    msg(5, "assistant", "", others[4]),
    msg(6, "assistant", "", crm),
    msg(7, "assistant", "", others[2]),
    msg(8, "assistant", "", others[5]),
    msg(9, "assistant", "", others[1]),
    msg(0, "system", "Some calendars couldn't be reached."),
    msg(10, "user", "/archive renewal with acme.com"),
    msg(11, "assistant", "", archive_list),
    msg(12, "assistant", "", archived_thread),
]
# --long: the conversation five times over, with long email bodies, as a real chat gets.
if "--long" in sys.argv:
    long_body = "\n\n".join(f"Paragraph {n}: " + "We went through the Q4 numbers line by line and agreed the forecast. " * 6 for n in range(1, 13))
    longer = []
    for round in range(5):
        for m in messages:
            copy = json.loads(json.dumps(m))
            copy["id"] = f"5A277C52-0000-4000-{8001 + round:04X}-{int(m['id'][-12:]):012d}"
            card = copy.get("card", {})
            for message in card.get("thread", {}).get("_0", {}).get("messages", []):
                message["body"] = long_body
            longer.append(copy)
    messages = longer
NOTES = [
    msg(1, "user", "/obsidian ntt"),
    msg(2, "assistant", "", note_choices),
    msg(3, "user", "/obsidian A"),
    msg(4, "assistant", "", note_view),
    msg(5, "assistant", "", crm_preview),
]
C2 = "5A277C52-1D0B-4A43-9C9E-2D5B8F1E0B00"
C3 = "5A277C52-1D0B-4A43-9C9E-2D5B8F1E0C00"

def day(offset):
    return (datetime.date.today() + datetime.timedelta(days=offset)).isoformat()

TASKS = [
    msg(1, "user", "/tasks"),
    msg(2, "assistant", "", {"tasks": {"_0": {"tasks": [
        {"id": "t1", "title": "Send Q4 numbers to Bob", "list": "Urgent", "completed": False, "dueDate": day(-2), "notes": "He asked twice", "link": "https://tasks.google.com/"},
        {"id": "t2", "title": "Dentist", "list": "Inbox", "completed": False, "dueDate": day(0), "notes": ""},
        {"id": "t3", "title": "Pay invoice", "list": "Inbox", "completed": True, "dueDate": day(0), "notes": ""},
        {"id": "t4", "title": "UOB follow-up", "list": "Inbox", "completed": False, "dueDate": day(3), "notes": "", "link": "https://tasks.google.com/"},
        {"id": "t5", "title": "Read the NTT report", "list": "Later", "completed": False, "notes": ""}],
        "lists": ["Inbox", "Urgent", "Later"], "problems": [], "busy": ["t2"], "readAt": "2026-11-14T09:00:00Z"}}}),
    msg(3, "user", "/task Call Bob Friday"),
    msg(4, "assistant", "", {"taskDraft": {"_0": {"title": "Call Bob", "list": "Inbox", "dueDate": day(6), "notes": "About Q4",
        "lists": ["Inbox", "Urgent", "Later"], "stage": "editing", "suggestingTitle": False, "titleBy": "summary · gemini"}}}),
    msg(5, "user", "move the dentist to Monday"),
    msg(6, "assistant", "", {"taskChange": {"_0": {"task": {"id": "t2", "title": "Dentist", "list": "Inbox", "completed": False, "dueDate": day(0), "notes": ""},
        "change": {"reschedule": {"dueDate": day(2)}}, "stage": "confirming"}}}),
]
CONV = {"conversation": {"id": C1, "title": "Unread this morning", "createdAt": "2026-11-13T08:00:00Z",
                         "updatedAt": "2026-11-13T08:05:00Z", "messages": messages},
        "chatStatus": "Searching email (from Bob · last 2 days)…", "answering": True, "busyMessages": []}
LIST = [{"id": C3, "title": "Tasks", "createdAt": "2026-11-13T08:00:00Z", "updatedAt": "2026-11-13T09:00:00Z"},
        {"id": C1, "title": "Unread this morning", "createdAt": "2026-11-13T08:00:00Z", "updatedAt": "2026-11-13T08:05:00Z"},
        {"id": "5A277C52-1D0B-4A43-9C9E-2D5B8F1E0B00", "title": "Notes: UOB and NTT", "createdAt": "2026-11-12T08:00:00Z", "updatedAt": "2026-11-12T09:00:00Z"}]

# As the desktop's /help lists them (GET /v1/commands).
COMMANDS = [{"name": n, "args": a, "summary": s} for n, a, s in [
    ("/unread", "[n]", "newest unread email"), ("/inbox", "[n]", "newest email, read and unread"),
    ("/search", "<words>", "search every server"), ("/open", "<n>", "open card n of the last list"),
    ("/summary", "[n]", "summarise card n"), ("/draft", "[n] [instructions]", "write a reply in the draft editor"),
    ("/drafts", "[n]", "your drafts"), ("/today", "", "today's events"), ("/events", "[days|words]", "upcoming events"),
    ("/learn", "[n]", "suggested notes from your edits"), ("/memory", "[n]", "your notes and the signature"),
    ("/crm", "[text]", "post an update to a project note"), ("/archive", "[words] [with person]", "search the archive"), ("/obsidian", "[n]", "add card n to an Obsidian note"),
    ("/rename", "<title>", "rename this chat"), ("/mcp", "[status|start|stop|restart] [server]", "the mail servers"),
    ("/help", "", "lists the commands")]]

# Events for the open streams: Add to note on the thread answers as the Mac does, with a placeholder
# ("Preparing an entry for your notes…") and then the notes card in its place.
EVENTS = []
EVENTS_LOCK = threading.Lock()

def push(event):
    with EVENTS_LOCK: EVENTS.append(json.dumps(event))

def add_to_notes(conversation):
    placeholder = {"id": str(uuid.uuid4()).upper(), "role": "assistant", "text": "Preparing an entry for your notes…",
                   "createdAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    push({"type": "message_appended", "conversationID": conversation, "message": placeholder})
    def later():
        time.sleep(2)
        push({"type": "message_updated", "conversationID": conversation, "message": dict(placeholder, text="", card=others[4])})
    threading.Thread(target=later, daemon=True).start()

def summarize(conversation, message_id):
    """Summary on a thread: the card turns to its Summary side, which streams in, as the Mac's does."""
    original = next((m for m in messages if m["id"] == message_id and "thread" in m.get("card", {})), None)
    if original is None: return
    def stream():
        words = ("Bob wants the Q4 numbers approved by Friday. He has gone through them line by line "
                 "with the team and agreed the forecast; Carol is copied in. Nothing else is needed.").split()
        for n in range(1, len(words) + 1, 3):
            message = json.loads(json.dumps(original))
            card = message["card"]["thread"]["_0"]
            card["side"] = "summary"
            done = n + 3 > len(words)
            card["summary"] = {"text": " ".join(words[:n + 2]), "state": {"done": {}} if done else {"writing": {}}, "by": "summary · gemini"}
            push({"type": "message_updated", "conversationID": conversation, "message": message})
            time.sleep(0.15)
    threading.Thread(target=stream, daemon=True).start()

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def send_json(self, code, body):
        data = body.encode() if isinstance(body, str) else json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data))); self.send_header("Connection", "close"); self.end_headers()
        self.wfile.write(data)
    def handle_any(self, method):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode() if length else ""
        path = self.path.split("?")[0]
        print(f"{method} {self.path} {body}"[:200], flush=True)
        if path == "/health": return self.send_json(200, {"ok": True})
        if self.headers.get("Authorization") != f"Bearer {TOKEN}": return self.send_json(401, {"error": "Unauthorized"})
        if method == "GET" and path == "/v1/info": return self.send_json(200, dict(json.loads(fx("info.json")), crmSection="CRM", crmConfigured=True, tasksConfigured=True))
        if method == "GET" and path == "/v1/conversations": return self.send_json(200, LIST)
        if method == "GET" and path == f"/v1/conversations/{C3}":
            return self.send_json(200, dict(CONV, conversation=dict(CONV["conversation"], id=C3, title="Tasks", messages=TASKS), chatStatus=None, answering=False))
        if method == "GET" and path == f"/v1/conversations/{C2}":
            return self.send_json(200, dict(CONV, conversation=dict(CONV["conversation"], id=C2, title="Notes: UOB and NTT", messages=NOTES), chatStatus=None, answering=False))
        if method == "GET" and path.startswith("/v1/conversations/"): return self.send_json(200, CONV)
        global EDITOR
        if method == "GET" and path == "/v1/editors":
            if not EDITOR: return self.send_json(200, [])
            editor = json.loads(fx("editor-reply.json"))
            editor["status"] = {"idle": {}}
            editor["form"]["body"] = "Hi Bob,\n\nThanks for sending the Q4 numbers. I'll have a look today and get back to you by Friday.\n"
            return self.send_json(200, [editor])
        if path.startswith("/v1/editors/") and (method == "DELETE" or path.endswith("/save")):
            EDITOR = False
            return self.send_json(202, {"ok": True})
        if method == "GET" and path == "/v1/commands": return self.send_json(200, COMMANDS)
        if method == "GET" and path == "/v1/history/search":
            return self.send_json(200, [{"conversationID": C1, "title": "Unread this morning", "updatedAt": "2026-11-13T08:05:00Z", "snippet": "Bob wants approval of Q4", "byMeaning": True, "messageID": CONV["conversation"]["messages"][0]["id"]}])
        if method == "GET" and path == "/v1/events":
            self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.send_header("Connection", "close"); self.end_headers()
            with EVENTS_LOCK: sent = len(EVENTS)
            last_ping = 0
            try:
                while True:
                    with EVENTS_LOCK: fresh = EVENTS[sent:]; sent = len(EVENTS)
                    for event in fresh: self.wfile.write(f"data: {event}\n\n".encode())
                    if time.time() - last_ping > 5: self.wfile.write(b": ping\n\n"); last_ping = time.time()
                    self.wfile.flush(); time.sleep(0.2)
            except Exception: return
        if method == "POST" and path.endswith("/open"):
            # Opening a list row: the thread arrives as a new card, as on the Mac.
            opened = json.loads(json.dumps(next(m for m in messages if "thread" in m.get("card", {}))))
            opened["id"] = str(uuid.uuid4()).upper()
            push({"type": "message_appended", "conversationID": path.split("/")[3], "message": opened})
        if method == "POST" and path.endswith("/action") and '"set_side"' in body and '"summary"' in body:
            summarize(path.split("/")[3], path.split("/")[5])
        if method == "POST" and path.endswith("/action") and '"add_to_notes"' in body:
            add_to_notes(path.split("/")[3])
        return self.send_json(202, {"ok": True})
    def do_GET(self): self.handle_any("GET")
    def do_POST(self): self.handle_any("POST")
    def do_PATCH(self): self.handle_any("PATCH")
    def do_DELETE(self): self.handle_any("DELETE")

print(f"Pretend Mac on http://127.0.0.1:{PORT}, token fum_smoke. Ctrl-C stops it.", flush=True)
ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
