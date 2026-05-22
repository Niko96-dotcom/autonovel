import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";

const h = React.createElement;

const DEFAULT_FORM = {
  provider_id: "openai",
  openai_api_key: "",
  openai_base_url: "",
  fal_key: "",
  elevenlabs_api_key: "",
  writer_model: "gpt-4o-mini",
  reviewer_model: "gpt-4o-mini",
  seed_concept: "",
  target_chapters: 2,
  target_word_count: 6000,
  foundation_threshold: 7.5,
  chapter_threshold: 6.0,
  voice_preferences: "",
  generate_cover: false,
  generate_audiobook: false,
  generate_pdf: true,
};

const FOUNDATION_FILES = ["world.md", "characters.md", "outline.md", "voice.md", "canon.md", "MYSTERY.md"];
const TABS = ["Foundation", "Drafting", "Revision", "Final review", "Export"];
const DEFAULT_PROVIDERS = [
  {
    id: "openai",
    name: "OpenAI",
    base_url: "",
    writer_model: "gpt-4o-mini",
    reviewer_model: "gpt-4o-mini",
    models: ["gpt-4o-mini", "gpt-4o", "gpt-5-mini"],
  },
  {
    id: "opencode-go",
    name: "OpenCode Go",
    base_url: "https://opencode.ai/zen/go/v1",
    writer_model: "minimax-m2.7",
    reviewer_model: "minimax-m2.7",
    models: [
      "minimax-m2.7",
      "minimax-m2.5",
      "kimi-k2.6",
      "kimi-k2.5",
      "glm-5.1",
      "glm-5",
      "deepseek-v4-pro",
      "deepseek-v4-flash",
      "qwen3.6-plus",
      "qwen3.5-plus",
      "mimo-v2-pro",
      "mimo-v2-omni",
      "mimo-v2.5-pro",
      "mimo-v2.5",
      "hy3-preview",
    ],
  },
  {
    id: "minimax",
    name: "MiniMax",
    base_url: "https://api.minimax.io/v1",
    writer_model: "MiniMax-M2.7",
    reviewer_model: "MiniMax-M2.7",
    models: [
      "MiniMax-M2.7",
      "MiniMax-M2.7-highspeed",
      "MiniMax-M2.5",
      "MiniMax-M2.5-highspeed",
      "MiniMax-M2.1",
      "MiniMax-M2.1-highspeed",
      "MiniMax-M2",
    ],
  },
  {
    id: "deepseek",
    name: "DeepSeek",
    base_url: "https://api.deepseek.com",
    writer_model: "deepseek-v4-pro",
    reviewer_model: "deepseek-v4-pro",
    models: ["deepseek-v4-pro", "deepseek-v4-flash"],
  },
];

function api(path, options) {
  return fetch(path, options).then(async (res) => {
    if (!res.ok) throw new Error((await res.text()) || res.statusText);
    return res.json();
  });
}

function markdown(text) {
  const escaped = text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
  return escaped
    .replace(/^### (.*)$/gm, "<h3>$1</h3>")
    .replace(/^## (.*)$/gm, "<h2>$1</h2>")
    .replace(/^# (.*)$/gm, "<h1>$1</h1>")
    .replace(/\*\*(.*?)\*\*/g, "<strong>$1</strong>")
    .replace(/\n\n/g, "</p><p>");
}

function groupArtifacts(artifacts) {
  return {
    Foundation: artifacts.filter((a) => FOUNDATION_FILES.includes(a.path)),
    Drafting: artifacts.filter((a) => a.path.startsWith("chapters/") || a.path.startsWith("eval_logs/")),
    Revision: artifacts.filter((a) => a.path.startsWith("edit_logs/") || a.path.startsWith("briefs/")),
    "Final review": artifacts.filter((a) => a.path === "reviews.md" || a.path.includes("_review.json")),
    Export: artifacts.filter((a) => ["manuscript.md", "arc_summary.md"].includes(a.path) || a.path.startsWith("typeset/") || a.path.startsWith("audiobook/") || a.path.startsWith("art/")),
  };
}

function newestPhase(events) {
  const phaseEvent = [...events].reverse().find((e) => e.event_type === "phase_started" || e.payload?.text?.startsWith("PHASE"));
  return phaseEvent?.phase || "setup";
}

function App() {
  const [form, setForm] = useState(DEFAULT_FORM);
  const [providers, setProviders] = useState(DEFAULT_PROVIDERS);
  const [runs, setRuns] = useState([]);
  const [selected, setSelected] = useState(null);
  const [events, setEvents] = useState([]);
  const [activeTab, setActiveTab] = useState("Foundation");
  const [artifactText, setArtifactText] = useState("");
  const [artifactPath, setArtifactPath] = useState("");
  const [error, setError] = useState("");
  const [providerMessage, setProviderMessage] = useState("");

  const artifacts = selected?.artifacts || [];
  const grouped = useMemo(() => groupArtifacts(artifacts), [artifacts]);
  const manifest = selected?.manifest;
  const running = manifest?.status === "running";
  const currentPhase = newestPhase(events);
  const selectedProvider = providers.find((provider) => provider.id === form.provider_id) || providers[0];
  const hasUsableKey = Boolean(form.openai_api_key.trim() || selectedProvider?.has_saved_key);
  const canStart = hasUsableKey && form.seed_concept.trim();

  async function refreshProviders() {
    const data = await api("/api/providers");
    setProviders(data.providers);
  }

  async function refreshRuns() {
    const data = await api("/api/runs");
    setRuns(data.runs);
  }

  async function loadRun(id) {
    const data = await api(`/api/runs/${id}`);
    setSelected(data);
    setEvents([]);
    setArtifactText("");
    setArtifactPath("");
  }

  useEffect(() => {
    refreshProviders().catch((err) => setError(err.message));
    refreshRuns().catch((err) => setError(err.message));
  }, []);

  useEffect(() => {
    if (!manifest?.id) return;
    const source = new EventSource(`/api/runs/${manifest.id}/events`);
    source.onmessage = (message) => {
      const event = JSON.parse(message.data);
      setEvents((prev) => [...prev, event]);
      loadRun(manifest.id).catch(() => {});
    };
    source.onerror = () => source.close();
    return () => source.close();
  }, [manifest?.id]);

  function update(name, value) {
    setForm((prev) => ({ ...prev, [name]: value }));
  }

  async function saveProviderKey() {
    setError("");
    setProviderMessage("");
    try {
      const data = await api("/api/provider-keys", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ provider_id: form.provider_id, api_key: form.openai_api_key }),
      });
      setProviders(data.providers);
      setForm((prev) => ({ ...prev, openai_api_key: "" }));
      setProviderMessage(`Saved key for ${selectedProvider?.name || "provider"}.`);
    } catch (err) {
      setError(err.message);
    }
  }

  async function startRun() {
    setError("");
    const estimate = `Estimated cost depends on model/provider and retry count. Current request: ${form.target_chapters} chapters, optional PDF ${form.generate_pdf ? "on" : "off"}, cover ${form.generate_cover ? "on" : "off"}, audiobook ${form.generate_audiobook ? "on" : "off"}.`;
    if (!window.confirm(`${estimate}\n\nStart run?`)) return;
    const payload = { ...form };
    for (const key of Object.keys(payload)) {
      if (payload[key] === "") payload[key] = null;
    }
    try {
      const run = await api("/api/runs", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      await refreshRuns();
      await loadRun(run.id);
    } catch (err) {
      setError(err.message);
    }
  }

  async function stopRun() {
    if (!manifest?.id) return;
    await api(`/api/runs/${manifest.id}`, { method: "DELETE" });
    await loadRun(manifest.id);
    await refreshRuns();
  }

  async function openArtifact(path) {
    if (!manifest?.id) return;
    const res = await fetch(`/api/runs/${manifest.id}/artifacts/${path}`);
    setArtifactPath(path);
    setArtifactText(await res.text());
  }

  return h("div", { className: "min-h-screen" },
    h("header", { className: "sticky top-0 z-10 border-b border-zinc-200 bg-white/95 backdrop-blur" },
      h("div", { className: "mx-auto flex max-w-7xl items-center justify-between px-5 py-3" },
        h("div", null,
          h("div", { className: "text-lg font-semibold" }, "Autonovel"),
          h("div", { className: "text-xs text-zinc-500" }, manifest ? manifest.id : "No run selected")
        ),
        h("div", { className: "grid grid-cols-4 gap-4 text-sm" },
          h("div", null, h("div", { className: "text-xs text-zinc-500" }, "Phase"), h("div", { className: "font-medium" }, currentPhase)),
          h("div", null, h("div", { className: "text-xs text-zinc-500" }, "Status"), h("div", { className: "font-medium" }, manifest?.status || "idle")),
          h("div", null, h("div", { className: "text-xs text-zinc-500" }, "Model"), h("div", { className: "font-medium" }, manifest?.config?.writer_model || form.writer_model)),
          h("div", null, h("div", { className: "text-xs text-zinc-500" }, "Tokens"), h("div", { className: "font-medium" }, "pending"))
        ),
        h("button", { className: "rounded bg-zinc-950 px-3 py-2 text-sm text-white disabled:opacity-40", disabled: !running, onClick: stopRun }, "Stop")
      )
    ),
    h("main", { className: "mx-auto grid max-w-7xl grid-cols-[360px_1fr_260px] gap-5 px-5 py-5" },
      h(SetupPanel, { form, update, providers, selectedProvider, providerMessage, saveProviderKey, canStart, startRun }),
      h(RunView, { manifest, events, grouped, activeTab, setActiveTab, openArtifact, artifactText, artifactPath }),
      h(History, { runs, loadRun })
    ),
    error && h("div", { className: "fixed bottom-4 left-1/2 -translate-x-1/2 rounded bg-red-700 px-4 py-2 text-sm text-white" }, error)
  );
}

function SetupPanel({ form, update, providers, selectedProvider, providerMessage, saveProviderKey, canStart, startRun }) {
  function applyProvider(provider) {
    setProviderForm(provider);
  }

  function setProviderForm(provider) {
    update("provider_id", provider.id);
    update("openai_base_url", provider.base_url);
    update("writer_model", provider.writer_model);
    update("reviewer_model", provider.reviewer_model);
    update("openai_api_key", "");
  }

  return h("section", { className: "space-y-4" },
    h("div", { className: "rounded border border-zinc-200 bg-white p-4" },
      h("h2", { className: "mb-3 text-sm font-semibold uppercase tracking-wide text-zinc-500" }, "Setup"),
      h("div", { className: "mb-3 grid grid-cols-2 gap-2" }, providers.map((provider) =>
        h("button", {
          key: provider.name,
          type: "button",
          className: `rounded border px-2 py-2 text-xs ${form.provider_id === provider.id ? "border-zinc-950 bg-zinc-950 text-white" : "border-zinc-300 bg-white"}`,
          onClick: () => applyProvider(provider),
        }, `${provider.name}${provider.has_saved_key ? " *" : ""}`)
      )),
      field("API key", "openai_api_key", "password", form, update, { placeholder: selectedProvider?.has_saved_key ? "Saved key will be used" : "Paste key, then Save key" }),
      h("button", {
        type: "button",
        className: "mb-3 w-full rounded border border-zinc-300 px-3 py-2 text-sm disabled:opacity-40",
        disabled: !form.provider_id || !form.openai_api_key.trim(),
        onClick: saveProviderKey,
      }, `Save ${selectedProvider?.name || "provider"} key`),
      providerMessage && h("div", { className: "mb-3 rounded bg-emerald-50 px-3 py-2 text-xs text-emerald-800" }, providerMessage),
      field("Base URL", "openai_base_url", "text", form, update),
      field("FAL key", "fal_key", "password", form, update),
      field("ElevenLabs key", "elevenlabs_api_key", "password", form, update),
      field("Writer model", "writer_model", "text", form, update),
      modelSelect("Writer preset", "writer_model", form, update, providers),
      field("Reviewer model", "reviewer_model", "text", form, update),
      modelSelect("Reviewer preset", "reviewer_model", form, update, providers)
    ),
    h("div", { className: "rounded border border-zinc-200 bg-white p-4" },
      h("h2", { className: "mb-3 text-sm font-semibold uppercase tracking-wide text-zinc-500" }, "Pipeline"),
      textarea("Seed concept", "seed_concept", form, update),
      field("Target chapters", "target_chapters", "number", form, update),
      field("Target word count", "target_word_count", "number", form, update),
      field("Foundation threshold", "foundation_threshold", "number", form, update),
      field("Chapter threshold", "chapter_threshold", "number", form, update),
      textarea("Voice preferences", "voice_preferences", form, update),
      toggle("Cover", "generate_cover", form, update),
      toggle("Audiobook", "generate_audiobook", form, update),
      toggle("LaTeX PDF", "generate_pdf", form, update),
      h("button", { className: "mt-4 w-full rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white disabled:opacity-40", disabled: !canStart, onClick: startRun }, "Start Run")
    )
  );
}

function field(label, name, type, form, update, options = {}) {
  return h("label", { className: "mb-3 block text-sm" },
    h("span", { className: "mb-1 block text-zinc-600" }, label),
    h("input", { className: "w-full rounded border border-zinc-300 px-3 py-2", type, value: form[name] ?? "", placeholder: options.placeholder || "", onChange: (e) => update(name, type === "number" ? Number(e.target.value) : e.target.value) })
  );
}

function textarea(label, name, form, update) {
  return h("label", { className: "mb-3 block text-sm" },
    h("span", { className: "mb-1 block text-zinc-600" }, label),
    h("textarea", { className: "min-h-28 w-full rounded border border-zinc-300 px-3 py-2", value: form[name] ?? "", onChange: (e) => update(name, e.target.value) })
  );
}

function toggle(label, name, form, update) {
  return h("label", { className: "mb-2 flex items-center justify-between text-sm" },
    h("span", { className: "text-zinc-700" }, label),
    h("input", { type: "checkbox", checked: Boolean(form[name]), onChange: (e) => update(name, e.target.checked) })
  );
}

function modelSelect(label, name, form, update, providers) {
  const current = form[name] ?? "";
  const knownModels = new Set(providers.flatMap((provider) => provider.models || []));
  return h("label", { className: "mb-3 block text-sm" },
    h("span", { className: "mb-1 block text-zinc-600" }, label),
    h("select", {
      className: "w-full rounded border border-zinc-300 bg-white px-3 py-2",
      value: current,
      onChange: (event) => update(name, event.target.value),
    },
      h("option", { value: "" }, "Custom"),
      current && !knownModels.has(current) && h("option", { value: current }, current),
      providers.map((provider) =>
        h("optgroup", { key: provider.id, label: provider.name }, (provider.models || []).map((model) =>
          h("option", { key: `${provider.id}:${model}`, value: model }, model)
        ))
      )
    )
  );
}

function RunView({ manifest, events, grouped, activeTab, setActiveTab, openArtifact, artifactText, artifactPath }) {
  return h("section", { className: "min-w-0 rounded border border-zinc-200 bg-white" },
    h("div", { className: "border-b border-zinc-200 px-4 py-3" },
      h("div", { className: "flex gap-2" }, TABS.map((tab) =>
        h("button", { key: tab, className: `rounded px-3 py-2 text-sm ${activeTab === tab ? "bg-zinc-950 text-white" : "bg-zinc-100"}`, onClick: () => setActiveTab(tab) }, tab)
      ))
    ),
    h("div", { className: "grid grid-cols-[260px_1fr] gap-0" },
      h("div", { className: "max-h-[calc(100vh-150px)] overflow-auto border-r border-zinc-200 p-3" },
        h("h3", { className: "mb-2 text-sm font-semibold" }, activeTab),
        (grouped[activeTab] || []).map((artifact) =>
          h("button", { key: artifact.path, className: "mb-1 block w-full rounded px-2 py-2 text-left text-sm hover:bg-zinc-100", onClick: () => openArtifact(artifact.path) }, artifact.path)
        ),
        activeTab === "Drafting" && h(ChapterTable, { artifacts: grouped.Drafting || [], openArtifact }),
        h("h3", { className: "mb-2 mt-5 text-sm font-semibold" }, "Events"),
        h("div", { className: "space-y-1" }, events.slice(-20).reverse().map((event, index) =>
          h("div", { key: index, className: "rounded bg-zinc-50 px-2 py-1 text-xs" }, `${event.event_type}: ${event.payload?.text || event.phase}`)
        ))
      ),
      h("div", { className: "max-h-[calc(100vh-150px)] overflow-auto p-5" },
        !manifest && h("div", { className: "text-zinc-500" }, "Select or start a run."),
        artifactPath && h("div", { className: "mb-3 text-sm font-medium text-zinc-500" }, artifactPath),
        artifactText
          ? h("article", { className: "prose prose-zinc max-w-none whitespace-normal", dangerouslySetInnerHTML: { __html: `<p>${markdown(artifactText)}</p>` } })
          : manifest && h("pre", { className: "whitespace-pre-wrap rounded bg-zinc-50 p-4 text-xs" }, JSON.stringify(manifest, null, 2))
      )
    )
  );
}

function ChapterTable({ artifacts, openArtifact }) {
  const chapters = artifacts.filter((a) => a.path.startsWith("chapters/ch_"));
  if (!chapters.length) return null;
  return h("table", { className: "mt-3 w-full text-xs" },
    h("tbody", null, chapters.map((artifact) =>
      h("tr", { key: artifact.path, className: "border-t border-zinc-100" },
        h("td", { className: "py-1" }, artifact.path.match(/ch_(\d+)/)?.[1] || "?"),
        h("td", { className: "py-1" }, "kept"),
        h("td", { className: "py-1 text-right" }, `${Math.round(artifact.size / 1024)} KB`),
        h("td", { className: "py-1 text-right" }, h("button", { className: "underline", onClick: () => openArtifact(artifact.path) }, "open"))
      )
    ))
  );
}

function History({ runs, loadRun }) {
  return h("aside", { className: "rounded border border-zinc-200 bg-white p-4" },
    h("h2", { className: "mb-3 text-sm font-semibold uppercase tracking-wide text-zinc-500" }, "History"),
    h("div", { className: "space-y-2" }, runs.map((run) =>
      h("button", { key: run.id, className: "block w-full rounded border border-zinc-200 px-3 py-2 text-left text-sm hover:bg-zinc-50", onClick: () => loadRun(run.id) },
        h("div", { className: "font-medium" }, run.id),
        h("div", { className: "text-xs text-zinc-500" }, `${run.status} · ${run.config?.writer_model || ""}`)
      )
    ))
  );
}

createRoot(document.getElementById("root")).render(h(App));
