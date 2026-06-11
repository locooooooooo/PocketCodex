use hbb_common::{
    anyhow::{anyhow, bail, Context, Result},
    config::Config,
    log,
};
use serde_derive::{Deserialize, Serialize};
use serde_json::{json, Value};
#[cfg(windows)]
use std::os::windows::process::CommandExt;
use std::{
    collections::{hash_map::Entry, HashMap, HashSet},
    fs::{self, OpenOptions},
    io::{BufRead, BufReader, Read, Seek, SeekFrom, Write},
    net::{TcpListener, TcpStream},
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    sync::Mutex,
    time::{SystemTime, UNIX_EPOCH},
};

pub const ENABLED: &str = "codex-bridge-enabled";
pub const PORT: &str = "codex-bridge-port";
pub const PROJECTS: &str = "codex-bridge-projects";
pub const COMMAND: &str = "codex-bridge-command";
pub const REQUIRE_CONFIRMATION: &str = "codex-bridge-require-confirmation";
pub const WHISPER_COMMAND: &str = "codex-bridge-whisper-command";
pub const WHISPER_MODEL: &str = "codex-bridge-whisper-model";

const DEFAULT_PORT: u16 = 17_321;
const MAX_BODY_LEN: usize = 64 * 1024;
const MAX_REQUEST_LEN: usize = MAX_BODY_LEN + 8 * 1024;
const MAX_RESPONSE_TEXT: usize = 12_000;
const MAX_TASK_TIMELINE: usize = 64;
const MAX_TASK_RAW_EVENTS: usize = 48;
const MAX_REMOTE_SESSION_CATALOG_ITEMS: usize = 60;
const BRIDGE_START_RETRIES: usize = 20;
const BRIDGE_START_RETRY_MS: u64 = 250;
const RUN_REQUEST_RECOVERY_RETRIES: usize = 12;
const RUN_REQUEST_RECOVERY_RETRY_MS: u64 = 500;
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

lazy_static::lazy_static! {
    static ref PENDING: Mutex<HashMap<String, PendingCommand>> = Default::default();
    static ref TASKS: Mutex<HashMap<String, AgentTaskInfo>> = Default::default();
    static ref SESSION_INDEX_CACHE: Mutex<Option<CodexSessionIndexCache>> = Default::default();
    static ref SESSION_FILE_CACHE: Mutex<HashMap<String, PathBuf>> = Default::default();
    static ref SESSION_LINE_INDEX_CACHE: Mutex<HashMap<PathBuf, CodexSessionLineIndexCache>> =
        Default::default();
}

#[derive(Debug, Clone)]
struct CodexSessionIndexCache {
    path: PathBuf,
    modified_at: Option<SystemTime>,
    len: u64,
    sessions: Vec<CodexSessionSummary>,
}

#[derive(Debug, Clone)]
struct CodexSessionLineIndexCache {
    modified_at: Option<SystemTime>,
    len: u64,
    lines: Vec<CodexSessionLineSpan>,
}

#[derive(Debug, Clone, Copy)]
struct CodexSessionLineSpan {
    start: u64,
    len: usize,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ProjectConfig {
    pub id: String,
    pub path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub executor: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session: Option<String>,
    #[serde(default)]
    pub resume_last: bool,
    #[serde(default)]
    pub allow_workspace_write: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thread_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub voice_language: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub whisper_command: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub whisper_model: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct AgentRunRequest {
    pub request_id: String,
    pub project: String,
    pub prompt: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub require_confirmation: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub executor: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resume_last: Option<bool>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AgentConfirmRequest {
    pub token: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AgentCancelRequest {
    pub request_id: Option<String>,
    pub token: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentResponse {
    pub request_id: String,
    pub project: String,
    pub status: String,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail_json: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentTimelineEvent {
    pub stage: String,
    pub summary: String,
    pub ts: u128,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub raw: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentTaskInfo {
    pub request_id: String,
    pub project: String,
    pub status: String,
    pub text: String,
    pub sandbox: String,
    pub started_at: u128,
    pub updated_at: u128,
    pub exit_code: Option<i32>,
    pub error: String,
    pub token: Option<String>,
    pub cancel_requested: bool,
    #[serde(default)]
    pub detail_json: String,
    #[serde(default)]
    pub timeline: Vec<AgentTimelineEvent>,
    #[serde(default)]
    pub raw_events: Vec<Value>,
}

#[derive(Debug, Clone, Serialize)]
pub struct BridgeConfigStatus {
    pub enabled: bool,
    pub port: u16,
    pub command: String,
    pub require_confirmation: bool,
    pub projects: Vec<ProjectStatus>,
    pub errors: Vec<String>,
    #[serde(default)]
    pub healthy: bool,
    #[serde(default)]
    pub health_error: String,
    #[serde(default)]
    pub last_start_error: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProjectStatus {
    pub id: String,
    pub path: String,
    pub display_name: String,
    pub exists: bool,
    pub executor: String,
    pub profile: String,
    pub session: String,
    pub resume_last: bool,
    pub allow_workspace_write: bool,
    pub thread_mode: String,
    pub tags: Vec<String>,
    pub voice_language: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct PublicAgentTaskInfo {
    pub request_id: String,
    pub project: String,
    pub status: String,
    pub text: String,
    pub sandbox: String,
    pub started_at: u128,
    pub updated_at: u128,
    pub exit_code: Option<i32>,
    pub error: String,
    pub cancel_requested: bool,
    #[serde(default)]
    pub detail_json: String,
    #[serde(default)]
    pub timeline: Vec<AgentTimelineEvent>,
}

#[derive(Debug, Clone)]
struct PendingCommand {
    request_id: String,
    target: ProjectConfig,
    prompt: String,
    conversation_id: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct AgentEnvelope {
    #[serde(default)]
    kind: Option<String>,
    #[serde(default)]
    action: Option<String>,
    #[serde(default)]
    conversation_id: Option<String>,
    #[serde(default)]
    prompt: Option<String>,
    #[serde(default)]
    route: Option<AgentRoute>,
    #[serde(default)]
    context: Option<AgentEnvelopeContext>,
    #[serde(default)]
    session_id: Option<String>,
    #[serde(default)]
    cursor: Option<usize>,
    #[serde(default)]
    page_size: Option<usize>,
    #[serde(default)]
    skill: Option<SkillCatalogUpsert>,
    #[serde(default)]
    skill_id: Option<String>,
    #[serde(default)]
    voice: Option<VoiceEnvelope>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct AgentRoute {
    #[serde(default)]
    project_id: Option<String>,
    #[serde(default)]
    project_path: Option<String>,
    #[serde(default)]
    thread_mode: Option<String>,
    #[serde(default)]
    active_thread_id: Option<String>,
    #[serde(default)]
    codex_thread_id: Option<String>,
    #[serde(default)]
    profile_id: Option<String>,
    #[serde(default)]
    selected_skill_ids: Vec<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct AgentEnvelopeContext {
    #[serde(default)]
    include_history: bool,
    #[serde(default)]
    include_terminal: bool,
    #[serde(default)]
    history_preview: Option<String>,
    #[serde(default)]
    terminal_snapshot: Option<String>,
    #[serde(default)]
    recent_files: Vec<String>,
    #[serde(default)]
    runtime_info: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct VoiceEnvelope {
    #[serde(default)]
    audio_base64: Option<String>,
    #[serde(default)]
    audio_path: Option<String>,
    #[serde(default)]
    language: Option<String>,
    #[serde(default)]
    normalized_prompt: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct CodexSessionSummary {
    id: String,
    #[serde(default, alias = "thread_name", alias = "title")]
    title: String,
    #[serde(default, alias = "updated_at", alias = "updatedAt")]
    updated_at: String,
    #[serde(default, alias = "projectId", skip_serializing_if = "String::is_empty")]
    project_id: String,
    #[serde(
        default,
        alias = "projectPath",
        skip_serializing_if = "String::is_empty"
    )]
    project_path: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct CodexSessionMessage {
    role: String,
    text: String,
    timestamp: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct CodexSessionDetail {
    id: String,
    title: String,
    updated_at: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    project_id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    project_path: String,
    messages: Vec<CodexSessionMessage>,
    timeline: Vec<AgentTimelineEvent>,
    raw_events: Vec<Value>,
    next_cursor: Option<usize>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct SkillCatalogEntry {
    id: String,
    title: String,
    group: String,
    description: String,
    enabled: bool,
    mirror_name: String,
    tags: Vec<String>,
    updated_at: u128,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
struct SkillCatalogFile {
    skills: Vec<SkillCatalogEntry>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct SkillCatalogUpsert {
    id: String,
    #[serde(default)]
    title: Option<String>,
    #[serde(default)]
    group: Option<String>,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    enabled: Option<bool>,
    #[serde(default)]
    mirror_name: Option<String>,
    #[serde(default)]
    tags: Option<Vec<String>>,
    #[serde(default)]
    content: Option<String>,
}

pub fn configured_port() -> u16 {
    if let Some(port) = std::env::var_os("RUSTDESK_CODEX_BRIDGE_PORT")
        .and_then(|value| value.to_string_lossy().parse::<u16>().ok())
    {
        return port;
    }
    Config::get_option(PORT).parse().unwrap_or(DEFAULT_PORT)
}

pub fn is_enabled() -> bool {
    Config::get_option(ENABLED) == "Y"
}

fn codex_command() -> String {
    let command = Config::get_option(COMMAND);
    if command.trim().is_empty() {
        "codex".to_owned()
    } else {
        command
    }
}

#[cfg(windows)]
fn resolved_codex_command() -> String {
    let command = codex_command();
    let trimmed = command.trim();
    if !trimmed.is_empty()
        && !trimmed.eq_ignore_ascii_case("codex")
        && !trimmed.eq_ignore_ascii_case("codex.cmd")
    {
        return command;
    }
    if let Ok(output) = Command::new("where.exe").arg("codex").output() {
        if output.status.success() {
            if let Some(path) =
                select_windows_codex_command_path(&String::from_utf8_lossy(&output.stdout))
            {
                return path.to_owned();
            }
        }
    }
    if trimmed.eq_ignore_ascii_case("codex.cmd") {
        "codex.cmd".to_owned()
    } else {
        command
    }
}

#[cfg(windows)]
fn select_windows_codex_command_path(where_output: &str) -> Option<&str> {
    let candidates = where_output
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>();

    for candidate in &candidates {
        let lower = candidate.replace('/', "\\").to_lowercase();
        if lower.ends_with("\\codex.cmd") && !lower.contains("\\windowsapps\\") {
            return Some(candidate);
        }
    }
    for candidate in &candidates {
        let lower = candidate.replace('/', "\\").to_lowercase();
        if lower.ends_with("\\codex.exe") && !lower.contains("\\windowsapps\\") {
            return Some(candidate);
        }
    }
    candidates.into_iter().find(|candidate| {
        candidate
            .replace('/', "\\")
            .to_lowercase()
            .ends_with("\\codex.cmd")
    })
}

#[cfg(not(windows))]
fn resolved_codex_command() -> String {
    codex_command()
}

fn requires_confirmation() -> bool {
    Config::get_option(REQUIRE_CONFIRMATION) != "N"
}

pub fn load_projects() -> Result<Vec<ProjectConfig>> {
    let raw = Config::get_option(PROJECTS);
    if raw.trim().is_empty() {
        return Ok(Vec::new());
    }
    let projects: Vec<ProjectConfig> =
        serde_json::from_str(&raw).context("Invalid codex-bridge-projects JSON")?;
    Ok(projects
        .into_iter()
        .filter(|p| !p.id.trim().is_empty() && !p.path.trim().is_empty())
        .collect())
}

fn resolve_target(req: &AgentRunRequest) -> Result<ProjectConfig> {
    let projects = load_projects()?;
    let mut target =
        if let Some(project) = projects.iter().find(|project| project.id == req.project) {
            project.clone()
        } else {
            resolve_project_from_session(req, &projects)?
        };
    if let Some(executor) = req
        .executor
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        target.executor = Some(executor.to_owned());
    }
    if let Some(profile) = req
        .profile
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        target.profile = Some(profile.to_owned());
    }
    if let Some(session) = req
        .session
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        if session.eq_ignore_ascii_case("@last") || session.eq_ignore_ascii_case("last") {
            target.session = None;
            target.resume_last = true;
        } else {
            target.session = Some(session.to_owned());
            target.resume_last = false;
        }
    }
    if let Some(resume_last) = req.resume_last {
        let has_explicit_session = target
            .session
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .is_some();
        if !(resume_last && has_explicit_session) {
            target.resume_last = resume_last;
            if resume_last {
                target.session = None;
            }
        }
    }
    Ok(target)
}

fn resolve_project_from_session(
    req: &AgentRunRequest,
    projects: &[ProjectConfig],
) -> Result<ProjectConfig> {
    let session = req
        .session
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("No session was provided for project fallback"))?;
    if session.eq_ignore_ascii_case("@last") || session.eq_ignore_ascii_case("last") {
        bail!("Cannot infer a project from last-session fallback")
    }
    let session_path = find_session_file_cached(session)
        .ok_or_else(|| anyhow!("Codex session file was not found: {session}"))?;
    let metadata = read_session_project_metadata(&session_path, projects)
        .with_context(|| format!("Failed to read Codex session metadata for {session}"))?;
    let project_path = metadata.project_path.trim();
    if project_path.is_empty() {
        bail!("Codex session does not include project metadata: {session}")
    }
    if !PathBuf::from(project_path).is_dir() {
        bail!("Codex session project path does not exist: {project_path}")
    }
    let project_id = req.project.trim();
    let resolved_id = if project_id.is_empty() {
        metadata.project_id
    } else {
        project_id.to_owned()
    };
    Ok(ProjectConfig {
        id: if resolved_id.trim().is_empty() {
            project_id_from_path(project_path)
        } else {
            resolved_id
        },
        path: project_path.to_owned(),
        display_name: None,
        tags: Vec::new(),
        executor: None,
        profile: None,
        session: Some(session.to_owned()),
        resume_last: false,
        allow_workspace_write: false,
        thread_mode: Some("continue".to_owned()),
        voice_language: None,
        whisper_command: None,
        whisper_model: None,
    })
}

pub fn health_url() -> String {
    format!("http://127.0.0.1:{}/health", configured_port())
}

pub fn run_url() -> String {
    format!("http://127.0.0.1:{}/agent/run", configured_port())
}

pub fn confirm_url() -> String {
    format!("http://127.0.0.1:{}/agent/confirm", configured_port())
}

pub fn task_url(request_id: &str) -> String {
    format!(
        "http://127.0.0.1:{}/agent/tasks/{request_id}",
        configured_port()
    )
}

pub fn cancel_url() -> String {
    format!("http://127.0.0.1:{}/agent/cancel", configured_port())
}

pub fn sessions_url() -> String {
    format!("http://127.0.0.1:{}/agent/sessions", configured_port())
}

pub fn session_detail_url(session_id: &str) -> String {
    format!(
        "http://127.0.0.1:{}/agent/sessions/{session_id}",
        configured_port()
    )
}

pub fn skills_url() -> String {
    format!("http://127.0.0.1:{}/agent/skills", configured_port())
}

pub fn voice_transcribe_url() -> String {
    format!(
        "http://127.0.0.1:{}/agent/voice/transcribe",
        configured_port()
    )
}

pub fn ensure_started() -> Result<()> {
    if health_check().is_ok() {
        return Ok(());
    }
    if !is_enabled() {
        bail!("Codex bridge is disabled. Set `{}` to `Y`.", ENABLED);
    }
    crate::run_me(vec!["--codex-bridge"]).context("Failed to start codex bridge")?;
    let mut last_error = String::new();
    for _ in 0..BRIDGE_START_RETRIES {
        std::thread::sleep(std::time::Duration::from_millis(BRIDGE_START_RETRY_MS));
        match health_check() {
            Ok(()) => return Ok(()),
            Err(err) => last_error = err.to_string(),
        }
    }
    bail!("Codex bridge did not become healthy: {last_error}")
}

pub fn health_check() -> Result<()> {
    let response = reqwest::blocking::get(health_url()).context("Codex bridge is not reachable")?;
    if response.status().is_success() {
        Ok(())
    } else {
        bail!("Codex bridge health check returned {}", response.status())
    }
}

pub fn send_run_request(req: &AgentRunRequest) -> Result<AgentResponse> {
    ensure_started()?;
    let response = reqwest::blocking::Client::new()
        .post(run_url())
        .json(req)
        .send();
    let response = match response {
        Ok(response) => response,
        Err(err) => {
            log::warn!(
                "codex bridge /agent/run transport error for request_id={}, project={}: {}",
                req.request_id,
                req.project,
                err
            );
            if let Some(response) = recover_run_request_via_task_status(req) {
                log::info!(
                    "Recovered /agent/run result from task status for request_id={}, status={}",
                    response.request_id,
                    response.status
                );
                return Ok(response);
            }
            return Err(err).context("Failed to send /agent/run to codex bridge");
        }
    };
    parse_bridge_response(response)
}

pub fn send_confirm_request(token: &str) -> Result<AgentResponse> {
    ensure_started()?;
    let response = reqwest::blocking::Client::new()
        .post(confirm_url())
        .json(&json!({ "token": token }))
        .send()
        .context("Failed to send /agent/confirm to codex bridge")?;
    parse_bridge_response(response)
}

pub fn send_cancel_request(id_or_token: &str) -> Result<Value> {
    send_cancel_request_parts(Some(id_or_token), Some(id_or_token))
}

pub fn send_cancel_request_parts(request_id: Option<&str>, token: Option<&str>) -> Result<Value> {
    ensure_started()?;
    let response = reqwest::blocking::Client::new()
        .post(cancel_url())
        .json(&json!({ "request_id": request_id, "token": token }))
        .send()
        .context("Failed to send /agent/cancel to codex bridge")?;
    parse_json_response(response)
}

pub fn send_task_status_request(request_id: &str) -> Result<AgentTaskInfo> {
    ensure_started()?;
    let response = reqwest::blocking::get(task_url(request_id))
        .context("Failed to send /agent/tasks request to codex bridge")?;
    serde_json::from_value(parse_json_response(response)?).context("Invalid codex bridge task")
}

fn recover_run_request_via_task_status(req: &AgentRunRequest) -> Option<AgentResponse> {
    for _ in 0..RUN_REQUEST_RECOVERY_RETRIES {
        std::thread::sleep(std::time::Duration::from_millis(
            RUN_REQUEST_RECOVERY_RETRY_MS,
        ));
        match send_task_status_request(&req.request_id) {
            Ok(task) => return Some(agent_response_from_task(task)),
            Err(err) => {
                log::debug!(
                    "Task recovery probe missed request_id={} after /agent/run transport error: {}",
                    req.request_id,
                    err
                );
            }
        }
    }
    None
}

fn agent_response_from_task(task: AgentTaskInfo) -> AgentResponse {
    let detail_json = task_snapshot_detail(&task).to_string();
    AgentResponse {
        request_id: task.request_id,
        project: task.project,
        status: task.status,
        text: task.text,
        token: task.token,
        detail_json: Some(detail_json),
    }
}

fn parse_bridge_response(response: reqwest::blocking::Response) -> Result<AgentResponse> {
    let text = parse_json_response(response)?;
    serde_json::from_value(text).context("Invalid codex bridge response")
}

fn parse_json_response(response: reqwest::blocking::Response) -> Result<Value> {
    let status = response.status();
    let text = response.text().unwrap_or_default();
    if !status.is_success() {
        if let Ok(value) = serde_json::from_str::<Value>(&text) {
            if let Some(error) = value.get("error").and_then(Value::as_str) {
                bail!("Codex bridge returned {}: {}", status, error);
            }
        }
        bail!("Codex bridge returned {}: {}", status, text);
    }
    serde_json::from_str(&text).context("Invalid codex bridge JSON response")
}

pub fn run_server() -> Result<()> {
    let port = configured_port();
    let addr = format!("127.0.0.1:{port}");
    let listener = TcpListener::bind(&addr).with_context(|| format!("Failed to bind {addr}"))?;
    log::info!("codex bridge listening on {}", addr);
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                std::thread::spawn(|| {
                    if let Err(err) = handle_stream(stream) {
                        log::warn!("codex bridge request failed: {}", err);
                    }
                });
            }
            Err(err) => log::warn!("codex bridge accept failed: {}", err),
        }
    }
    Ok(())
}

fn handle_stream(mut stream: TcpStream) -> Result<()> {
    let request = read_http_request(&mut stream)?;
    if request.is_empty() {
        return Ok(());
    }
    let (method, path, body) = parse_http_request(&request)?;
    let (status, response) = match handle_request(&method, &path, &body) {
        Ok(response) => (200, response),
        Err((status, err)) => {
            let error = err.to_string();
            append_audit(&json!({
                "event": "request_error",
                "method": method,
                "path": path,
                "error": error,
            }));
            (status, json!({ "error": error }))
        }
    };
    write_response(&mut stream, status, &response)
}

fn read_http_request(stream: &mut TcpStream) -> Result<String> {
    let mut buffer = Vec::new();
    let mut chunk = [0_u8; 4096];
    loop {
        let n = stream.read(&mut chunk)?;
        if n == 0 {
            break;
        }
        buffer.extend_from_slice(&chunk[..n]);
        if buffer.len() > MAX_REQUEST_LEN {
            bail!("HTTP request is too large");
        }
        if let Some((body_start, content_length)) = http_request_ready(&buffer)? {
            let total_len = body_start + content_length;
            if total_len > MAX_REQUEST_LEN {
                bail!("HTTP request is too large");
            }
            if buffer.len() >= total_len {
                buffer.truncate(total_len);
                break;
            }
        }
    }
    String::from_utf8(buffer).context("HTTP request is not valid UTF-8")
}

fn http_request_ready(buffer: &[u8]) -> Result<Option<(usize, usize)>> {
    let Some(body_start) = find_header_end(buffer) else {
        return Ok(None);
    };
    let head = std::str::from_utf8(&buffer[..body_start]).context("HTTP header is not UTF-8")?;
    let content_length = content_length(head)?;
    if content_length > MAX_BODY_LEN {
        bail!("HTTP request body is too large");
    }
    Ok(Some((body_start, content_length)))
}

fn find_header_end(buffer: &[u8]) -> Option<usize> {
    buffer
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .map(|position| position + 4)
}

fn content_length(head: &str) -> Result<usize> {
    for line in head.lines().skip(1) {
        let Some((name, value)) = line.split_once(':') else {
            continue;
        };
        if name.trim().eq_ignore_ascii_case("content-length") {
            return value.trim().parse().context("Invalid HTTP Content-Length");
        }
    }
    Ok(0)
}

fn handle_request(
    method: &str,
    path: &str,
    body: &str,
) -> std::result::Result<Value, (u16, String)> {
    let (route_path, query) = split_path_query(path);
    match (method, route_path.as_str()) {
        ("OPTIONS", _) => Ok(json!({ "status": "ok" })),
        ("GET", "/health") => Ok(json!({ "status": "ok" })),
        ("GET", "/agent/config") => serde_json::to_value(config_status())
            .map_err(|e| (500, format!("Failed to serialize config response: {e}"))),
        ("GET", "/agent/sessions") => serde_json::to_value(handle_sessions().map_err(error400)?)
            .map_err(|e| (500, format!("Failed to serialize sessions response: {e}"))),
        ("POST", "/agent/run") => {
            let req: AgentRunRequest = serde_json::from_str(body).map_err(error400)?;
            serde_json::to_value(handle_run(req).map_err(error400)?)
                .map_err(|e| (500, format!("Failed to serialize run response: {e}")))
        }
        ("POST", "/agent/confirm") => {
            let req: AgentConfirmRequest = serde_json::from_str(body).map_err(error400)?;
            serde_json::to_value(handle_confirm(req).map_err(error400)?)
                .map_err(|e| (500, format!("Failed to serialize confirm response: {e}")))
        }
        ("POST", "/agent/cancel") => {
            let req: AgentCancelRequest = serde_json::from_str(body).map_err(error400)?;
            Ok(handle_cancel(req).map_err(error400)?)
        }
        ("GET", "/agent/skills") => serde_json::to_value(handle_list_skills().map_err(error400)?)
            .map_err(|e| (500, format!("Failed to serialize skills response: {e}"))),
        ("POST", "/agent/skills") => {
            let req: SkillCatalogUpsert = serde_json::from_str(body).map_err(error400)?;
            serde_json::to_value(handle_upsert_skill(req).map_err(error400)?)
                .map_err(|e| (500, format!("Failed to serialize skill response: {e}")))
        }
        ("POST", "/agent/skills/sync") => Ok(handle_sync_skills().map_err(error400)?),
        ("POST", "/agent/voice/transcribe") => {
            let req: VoiceEnvelope = serde_json::from_str(body).map_err(error400)?;
            Ok(handle_voice_transcribe(req).map_err(error400)?)
        }
        ("POST", "/agent/voice/run") => {
            let req: AgentEnvelope = serde_json::from_str(body).map_err(error400)?;
            serde_json::to_value(handle_voice_run(req).map_err(error400)?)
                .map_err(|e| (500, format!("Failed to serialize voice run response: {e}")))
        }
        ("GET", path) if path.starts_with("/agent/tasks/") => {
            let request_id = path.trim_start_matches("/agent/tasks/").trim();
            serde_json::to_value(public_task_info(
                handle_task_status(request_id).map_err(error400)?,
            ))
            .map_err(|e| (500, format!("Failed to serialize task response: {e}")))
        }
        ("GET", path) if path.starts_with("/agent/sessions/") && path.ends_with("/page") => {
            let session_id = path
                .trim_start_matches("/agent/sessions/")
                .trim_end_matches("/page")
                .trim_end_matches('/')
                .trim();
            serde_json::to_value(public_session_detail(
                handle_session_page(session_id, query.as_deref()).map_err(error400)?,
            ))
            .map_err(|e| {
                (
                    500,
                    format!("Failed to serialize session page response: {e}"),
                )
            })
        }
        ("GET", path) if path.starts_with("/agent/sessions/") => {
            let session_id = path.trim_start_matches("/agent/sessions/").trim();
            serde_json::to_value(public_session_detail(
                handle_session_detail(session_id).map_err(error400)?,
            ))
            .map_err(|e| (500, format!("Failed to serialize session response: {e}")))
        }
        ("PUT", path) if path.starts_with("/agent/skills/") => {
            let skill_id = path.trim_start_matches("/agent/skills/").trim();
            let mut req: SkillCatalogUpsert = serde_json::from_str(body).map_err(error400)?;
            if req.id.trim().is_empty() {
                req.id = skill_id.to_owned();
            }
            serde_json::to_value(handle_upsert_skill(req).map_err(error400)?)
                .map_err(|e| (500, format!("Failed to serialize skill response: {e}")))
        }
        ("DELETE", path) if path.starts_with("/agent/skills/") => {
            let skill_id = path.trim_start_matches("/agent/skills/").trim();
            Ok(handle_delete_skill(skill_id).map_err(error400)?)
        }
        _ => Err((404, "not found".to_owned())),
    }
}

fn split_path_query(path: &str) -> (String, Option<String>) {
    if let Some((route, query)) = path.split_once('?') {
        (route.to_owned(), Some(query.to_owned()))
    } else {
        (path.to_owned(), None)
    }
}

fn error400<E: std::fmt::Display>(err: E) -> (u16, String) {
    (400, err.to_string())
}

fn config_status() -> BridgeConfigStatus {
    let mut errors = Vec::new();
    let projects = match load_projects() {
        Ok(projects) => projects,
        Err(err) => {
            errors.push(err.to_string());
            Vec::new()
        }
    };
    let projects = projects
        .into_iter()
        .map(|project| {
            let exists = PathBuf::from(&project.path).is_dir();
            if !exists {
                errors.push(format!(
                    "Project `{}` path does not exist: {}",
                    project.id,
                    public_project_path_for_id(&project.id)
                ));
            }
            ProjectStatus {
                id: project.id,
                path: public_project_path(&project.path),
                display_name: project.display_name.unwrap_or_default(),
                exists,
                executor: project.executor.unwrap_or_else(|| "codex".to_owned()),
                profile: project.profile.unwrap_or_default(),
                session: project.session.unwrap_or_default(),
                resume_last: project.resume_last,
                allow_workspace_write: project.allow_workspace_write,
                thread_mode: project.thread_mode.unwrap_or_else(|| "new".to_owned()),
                tags: project.tags,
                voice_language: project.voice_language.unwrap_or_default(),
            }
        })
        .collect();
    BridgeConfigStatus {
        enabled: is_enabled(),
        port: configured_port(),
        command: codex_command(),
        require_confirmation: requires_confirmation(),
        projects,
        errors,
        healthy: false,
        health_error: String::new(),
        last_start_error: String::new(),
    }
}

pub fn config_status_with_probe(attempt_start: bool) -> BridgeConfigStatus {
    let mut status = config_status();
    match health_check() {
        Ok(()) => {
            status.healthy = true;
            return status;
        }
        Err(err) => {
            status.health_error = err.to_string();
        }
    }

    if attempt_start && status.enabled {
        match ensure_started() {
            Ok(()) => {
                status.healthy = true;
                status.health_error.clear();
            }
            Err(err) => {
                status.last_start_error = err.to_string();
            }
        }
    }

    status
}

fn parse_http_request(request: &str) -> Result<(String, String, String)> {
    let (head, body) = request
        .split_once("\r\n\r\n")
        .ok_or_else(|| anyhow!("Malformed HTTP request"))?;
    let mut lines = head.lines();
    let request_line = lines
        .next()
        .ok_or_else(|| anyhow!("Missing HTTP request line"))?;
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or_default().to_owned();
    let path = parts.next().unwrap_or_default().to_owned();
    Ok((method, path, body.to_owned()))
}

fn write_response(stream: &mut TcpStream, status: u16, body: &Value) -> Result<()> {
    let reason = match status {
        200 => "OK",
        204 => "No Content",
        400 => "Bad Request",
        404 => "Not Found",
        500 => "Internal Server Error",
        _ => "OK",
    };
    let body = serde_json::to_string(body)?;
    write!(
        stream,
        "HTTP/1.1 {status} {reason}\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nConnection: close\r\n\r\n{}",
        body.as_bytes().len(),
        body
    )?;
    Ok(())
}

fn handle_run(req: AgentRunRequest) -> Result<AgentResponse> {
    if let Some(envelope) = parse_agent_envelope(&req.prompt) {
        return handle_envelope_run(req, envelope);
    }
    execute_run_request(req, None)
}

fn execute_run_request(
    req: AgentRunRequest,
    conversation_id: Option<String>,
) -> Result<AgentResponse> {
    let project = resolve_target(&req)?;
    let mode = req.mode.as_deref().unwrap_or("read-only");
    let write_requested = mode.eq_ignore_ascii_case("workspace-write")
        || mode.eq_ignore_ascii_case("write")
        || mode.eq_ignore_ascii_case("workspace_write");
    if write_requested && !project.allow_workspace_write {
        return Ok(AgentResponse {
            request_id: req.request_id,
            project: project.id,
            status: "failed".to_owned(),
            text: "workspace-write is not allowed for this project.".to_owned(),
            token: None,
            detail_json: conversation_detail_json(
                conversation_id.as_deref(),
                Some(json!({
                    "kind": "error",
                    "code": "workspace_write_blocked",
                })),
            ),
        });
    }
    let require_confirmation = requires_confirmation() || req.require_confirmation.unwrap_or(false);
    upsert_task(
        &req.request_id,
        &project.id,
        "started",
        "Queued by RustDesk /agent route.",
        "read-only",
        None,
        "",
        None,
        conversation_detail_json(conversation_id.as_deref(), None),
        None,
    );
    if require_confirmation && (write_requested || looks_like_write_request(&req.prompt)) {
        return plan_for_write_confirmation(req.request_id, project, req.prompt, conversation_id);
    }
    let sandbox = if write_requested && !require_confirmation {
        "workspace-write"
    } else {
        "read-only"
    };
    spawn_codex_task(
        req.request_id.clone(),
        project.clone(),
        req.prompt,
        sandbox.to_owned(),
        conversation_id,
    );
    Ok(initial_task_response(&req.request_id, &project.id))
}

fn parse_agent_envelope(prompt: &str) -> Option<AgentEnvelope> {
    let trimmed = prompt.trim();
    if !trimmed.starts_with('{') {
        return None;
    }
    serde_json::from_str::<AgentEnvelope>(trimmed).ok()
}

fn handle_envelope_run(mut req: AgentRunRequest, envelope: AgentEnvelope) -> Result<AgentResponse> {
    let action = envelope
        .action
        .clone()
        .or(envelope.kind.clone())
        .unwrap_or_else(|| "run".to_owned());
    let conversation_id = envelope.conversation_id.clone();
    match action.as_str() {
        "list_sessions" => Ok(simple_dashboard_response(
            req.request_id,
            req.project,
            "done",
            "Loaded Codex sessions.",
            dashboard_detail(
                json!({
                "kind": "sessions",
                "items": limited_public_session_summaries(handle_sessions()?),
                }),
                conversation_id.as_deref(),
            ),
        )),
        "get_session" => {
            let session_id = envelope
                .session_id
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| anyhow!("session_id is required"))?;
            Ok(simple_dashboard_response(
                req.request_id,
                req.project,
                "done",
                "Loaded Codex session detail.",
                dashboard_detail(
                    json!({
                    "kind": "session_detail",
                    "item": public_session_detail(handle_session_detail(session_id)?),
                    }),
                    conversation_id.as_deref(),
                ),
            ))
        }
        "page_session" => {
            let session_id = envelope
                .session_id
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| anyhow!("session_id is required"))?;
            Ok(simple_dashboard_response(
                req.request_id,
                req.project,
                "done",
                "Loaded more session history.",
                dashboard_detail(
                    json!({
                    "kind": "session_page",
                    "item": public_session_detail(load_codex_session_detail(
                        session_id,
                        envelope.cursor,
                        envelope.page_size.unwrap_or(40),
                    )?),
                    }),
                    conversation_id.as_deref(),
                ),
            ))
        }
        "list_skills" => Ok(simple_dashboard_response(
            req.request_id,
            req.project,
            "done",
            "Loaded RustDesk skills catalog.",
            json!({
                "kind": "skills",
                "items": handle_list_skills()?,
            }),
        )),
        "upsert_skill" => Ok(simple_dashboard_response(
            req.request_id,
            req.project,
            "done",
            "Saved skill.",
            json!({
                "kind": "skill_saved",
                "item": handle_upsert_skill(
                    envelope.skill.ok_or_else(|| anyhow!("skill payload is required"))?
                )?,
            }),
        )),
        "delete_skill" => {
            let skill_id = envelope
                .skill_id
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| anyhow!("skill_id is required"))?;
            Ok(simple_dashboard_response(
                req.request_id,
                req.project,
                "done",
                "Deleted skill.",
                json!({
                    "kind": "skill_deleted",
                    "result": handle_delete_skill(skill_id)?,
                }),
            ))
        }
        "sync_skills" => Ok(simple_dashboard_response(
            req.request_id,
            req.project,
            "done",
            "Synced skills mirror.",
            json!({
                "kind": "skills_sync",
                "result": handle_sync_skills()?,
            }),
        )),
        "voice_transcribe" => Ok(simple_dashboard_response(
            req.request_id,
            req.project,
            "done",
            "Transcribed voice clip.",
            json!({
                "kind": "voice_transcribe",
                "result": handle_voice_transcribe(
                    envelope.voice.ok_or_else(|| anyhow!("voice payload is required"))?
                )?,
            }),
        )),
        "voice_run" => handle_voice_run(envelope),
        _ => {
            if let Some(route) = envelope.route.clone() {
                if let Some(project_id) = route.project_id.as_deref().map(str::trim) {
                    if !project_id.is_empty() {
                        req.project = project_id.to_owned();
                    }
                }
                if req.profile.is_none() {
                    req.profile = route.profile_id.clone();
                }
                if let Some(session) = route
                    .codex_thread_id
                    .clone()
                    .or(route.active_thread_id.clone())
                    .map(|value| value.trim().to_owned())
                    .filter(|value| !value.is_empty())
                {
                    req.session = Some(session);
                }
                req.resume_last = Some(matches!(route.thread_mode.as_deref(), Some("continue")));
            }
            let prompt = envelope.prompt.clone().unwrap_or_default();
            req.prompt = compose_envelope_prompt(
                &prompt,
                envelope.context.as_ref(),
                envelope.route.as_ref(),
            );
            execute_run_request(req, conversation_id)
        }
    }
}

fn simple_dashboard_response(
    request_id: String,
    project: String,
    status: &str,
    text: &str,
    detail: Value,
) -> AgentResponse {
    AgentResponse {
        request_id,
        project,
        status: status.to_owned(),
        text: text.to_owned(),
        token: None,
        detail_json: Some(detail.to_string()),
    }
}

fn dashboard_detail(mut detail: Value, conversation_id: Option<&str>) -> Value {
    if let Some(conversation_id) = conversation_id
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        if let Some(obj) = detail.as_object_mut() {
            obj.insert("conversationId".to_owned(), json!(conversation_id));
        }
    }
    detail
}

fn compose_envelope_prompt(
    prompt: &str,
    context: Option<&AgentEnvelopeContext>,
    route: Option<&AgentRoute>,
) -> String {
    let mut parts = Vec::new();
    if let Some(route) = route {
        if !route.selected_skill_ids.is_empty() {
            parts.push(format!(
                "Preferred skills: {}",
                route.selected_skill_ids.join(", ")
            ));
        }
    }
    if let Some(context) = context {
        if let Some(history) = context
            .history_preview
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty() && context.include_history)
        {
            parts.push(format!("Conversation history:\n{history}"));
        }
        if let Some(terminal) = context
            .terminal_snapshot
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty() && context.include_terminal)
        {
            parts.push(format!("Terminal snapshot:\n{terminal}"));
        }
        if !context.recent_files.is_empty() {
            parts.push(format!("Recent files: {}", context.recent_files.join(", ")));
        }
    }
    if parts.is_empty() {
        prompt.trim().to_owned()
    } else {
        parts.push(format!("Current request:\n{}", prompt.trim()));
        parts.join("\n\n")
    }
}

fn plan_for_write_confirmation(
    request_id: String,
    project: ProjectConfig,
    prompt: String,
    conversation_id: Option<String>,
) -> Result<AgentResponse> {
    let plan_prompt = format!(
        "The user asked for a change that may modify files. Do not write files. Analyze the request and return a concise execution plan, likely files, risks, and tests before confirmation.\n\nUser request:\n{prompt}"
    );
    let plan = run_codex(
        request_id.clone(),
        project.clone(),
        plan_prompt,
        "read-only",
        conversation_id.as_deref(),
    )?;
    if plan.status == "failed" {
        return Ok(plan);
    }

    let token = new_token();
    PENDING.lock().unwrap().insert(
        token.clone(),
        PendingCommand {
            request_id: request_id.clone(),
            target: project.clone(),
            prompt: prompt.clone(),
            conversation_id: conversation_id.clone(),
        },
    );
    upsert_task(
        &request_id,
        &project.id,
        "needs_confirmation",
        &plan.text,
        "read-only",
        None,
        "",
        Some(token.clone()),
        conversation_detail_json(
            conversation_id.as_deref(),
            Some(json!({
                "kind": "confirmation",
                "project": project.id,
                "requestId": request_id,
            })),
        ),
        Some(json!({
            "plan": plan.text,
            "token": token,
        })),
    );
    append_audit(&json!({
        "event": "needs_confirmation",
        "request_id": &request_id,
        "project": &project.id,
        "prompt": &prompt,
        "mode": "confirmation",
        "sandbox": "read-only",
        "token": &token,
        "summary": &plan.text,
    }));
    let project_id = project.id.clone();
    Ok(AgentResponse {
        request_id,
        project: project_id.clone(),
        status: "needs_confirmation".to_owned(),
        text: plan.text,
        token: Some(token),
        detail_json: conversation_detail_json(
            conversation_id.as_deref(),
            Some(json!({
                "kind": "confirmation",
                "project": project_id,
            })),
        ),
    })
}

fn handle_confirm(req: AgentConfirmRequest) -> Result<AgentResponse> {
    let pending = PENDING
        .lock()
        .unwrap()
        .remove(&req.token)
        .ok_or_else(|| anyhow!("Unknown or expired confirmation token"))?;
    let request_id = pending.request_id.clone();
    if task_cancel_requested(&request_id) {
        upsert_task(
            &request_id,
            &pending.target.id,
            "cancelled",
            "Task was cancelled before confirmation.",
            "workspace-write",
            None,
            "",
            None,
            None,
            None,
        );
        return Ok(AgentResponse {
            request_id,
            project: pending.target.id,
            status: "cancelled".to_owned(),
            text: "Task was cancelled before confirmation.".to_owned(),
            token: None,
            detail_json: None,
        });
    }
    let request_id = pending.request_id.clone();
    let project_id = pending.target.id.clone();
    spawn_codex_task(
        pending.request_id,
        pending.target,
        pending.prompt,
        "workspace-write".to_owned(),
        pending.conversation_id,
    );
    Ok(initial_task_response(&request_id, &project_id))
}

fn handle_task_status(request_id: &str) -> Result<AgentTaskInfo> {
    if request_id.is_empty() {
        bail!("Missing request_id")
    }
    TASKS
        .lock()
        .unwrap()
        .get(request_id)
        .cloned()
        .ok_or_else(|| anyhow!("Unknown task `{request_id}`"))
}

fn spawn_codex_task(
    request_id: String,
    project: ProjectConfig,
    prompt: String,
    sandbox: String,
    conversation_id: Option<String>,
) {
    std::thread::spawn(move || {
        let project_id = project.id.clone();
        match run_codex(
            request_id.clone(),
            project,
            prompt,
            &sandbox,
            conversation_id.as_deref(),
        ) {
            Ok(_) => {}
            Err(err) => {
                let error = err.to_string();
                log::warn!(
                    "codex task {} failed before completion: {}",
                    request_id,
                    error
                );
                upsert_task(
                    &request_id,
                    &project_id,
                    "failed",
                    &error,
                    &sandbox,
                    None,
                    &error,
                    None,
                    conversation_detail_json(
                        conversation_id.as_deref(),
                        Some(json!({
                            "kind": "error",
                            "message": error,
                        })),
                    ),
                    None,
                );
            }
        }
    });
}

fn initial_task_response(request_id: &str, project_id: &str) -> AgentResponse {
    let detail_json = handle_task_status(request_id)
        .ok()
        .map(|task| task_snapshot_detail(&task).to_string());
    AgentResponse {
        request_id: request_id.to_owned(),
        project: project_id.to_owned(),
        status: "running".to_owned(),
        text: "Codex is running.".to_owned(),
        token: None,
        detail_json,
    }
}

pub(crate) fn task_snapshot_detail(task: &AgentTaskInfo) -> Value {
    let item = serde_json::to_value(public_task_info(task.clone())).unwrap_or_else(|_| json!({}));
    let detail = parse_detail_json_value(&task.detail_json);
    let mut value = json!({
        "kind": "task_snapshot",
        "item": item,
    });
    if let Some(detail) = detail.map(redact_public_value) {
        if let Some(obj) = value.as_object_mut() {
            obj.insert("detail".to_owned(), detail);
        }
    }
    value
}

fn public_task_info(task: AgentTaskInfo) -> PublicAgentTaskInfo {
    PublicAgentTaskInfo {
        request_id: task.request_id,
        project: task.project,
        status: task.status,
        text: redact_sensitive_text(&task.text),
        sandbox: task.sandbox,
        started_at: task.started_at,
        updated_at: task.updated_at,
        exit_code: task.exit_code,
        error: redact_sensitive_text(&task.error),
        cancel_requested: task.cancel_requested,
        detail_json: public_detail_json(&task.detail_json),
        timeline: public_timeline(task.timeline),
    }
}

fn public_session_summaries(sessions: Vec<CodexSessionSummary>) -> Vec<CodexSessionSummary> {
    sessions.into_iter().map(public_session_summary).collect()
}

fn limited_public_session_summaries(
    sessions: Vec<CodexSessionSummary>,
) -> Vec<CodexSessionSummary> {
    sessions
        .into_iter()
        .take(MAX_REMOTE_SESSION_CATALOG_ITEMS)
        .map(public_session_summary)
        .collect()
}

fn public_session_summary(mut session: CodexSessionSummary) -> CodexSessionSummary {
    let project_id = if session.project_id.trim().is_empty() {
        project_id_from_path(&session.project_path)
    } else {
        session.project_id.clone()
    };
    session.project_path = public_project_path_for_id(&project_id);
    session
}

fn public_session_detail(mut detail: CodexSessionDetail) -> CodexSessionDetail {
    let project_id = if detail.project_id.trim().is_empty() {
        project_id_from_path(&detail.project_path)
    } else {
        detail.project_id.clone()
    };
    detail.project_path = public_project_path_for_id(&project_id);
    detail.messages = detail
        .messages
        .into_iter()
        .map(|mut message| {
            message.text = redact_sensitive_text(&message.text);
            message
        })
        .collect();
    detail.timeline = public_timeline(detail.timeline);
    detail.raw_events.clear();
    detail
}

fn public_timeline(timeline: Vec<AgentTimelineEvent>) -> Vec<AgentTimelineEvent> {
    timeline
        .into_iter()
        .map(|mut event| {
            event.summary = redact_sensitive_text(&event.summary);
            event.raw = None;
            event
        })
        .collect()
}

fn public_detail_json(raw: &str) -> String {
    parse_detail_json_value(raw)
        .map(redact_public_value)
        .map(|value| value.to_string())
        .unwrap_or_default()
}

fn public_project_path(path: &str) -> String {
    let id = project_id_from_path(path);
    public_project_path_for_id(&id)
}

fn public_project_path_for_id(project_id: &str) -> String {
    let id = public_project_id_segment(project_id);
    if id.is_empty() {
        "<PROJECT_PATH>".to_owned()
    } else {
        format!("<PROJECT_PATH>/{id}")
    }
}

fn public_project_id_segment(project_id: &str) -> String {
    project_id
        .trim()
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.') {
                ch
            } else {
                '-'
            }
        })
        .collect::<String>()
        .trim_matches('-')
        .to_owned()
}

fn redact_public_value(value: Value) -> Value {
    match value {
        Value::Array(items) => Value::Array(items.into_iter().map(redact_public_value).collect()),
        Value::Object(map) => Value::Object(
            map.into_iter()
                .map(|(key, value)| {
                    let lower = key.to_ascii_lowercase();
                    let redacted = if matches!(
                        lower.as_str(),
                        "cwd" | "path" | "project_path" | "projectpath" | "outputfile"
                    ) {
                        json!(public_project_path(value.as_str().unwrap_or_default()))
                    } else if lower.contains("token")
                        || lower.contains("secret")
                        || lower.contains("password")
                        || lower.contains("authorization")
                        || lower.contains("cookie")
                    {
                        json!("<redacted>")
                    } else {
                        redact_public_value(value)
                    };
                    (key, redacted)
                })
                .collect(),
        ),
        Value::String(text) => Value::String(redact_sensitive_text(&text)),
        other => other,
    }
}

fn redact_sensitive_text(text: &str) -> String {
    let without_tokens = redact_token_lines(text);
    redact_windows_paths(&without_tokens)
}

fn redact_token_lines(text: &str) -> String {
    text.lines()
        .map(|line| {
            if line.to_ascii_lowercase().trim_start().starts_with("token:") {
                "Token: <redacted>".to_owned()
            } else {
                line.to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn redact_windows_paths(text: &str) -> String {
    text.split_whitespace()
        .map(|part| {
            if looks_like_windows_path(part) {
                "<LOCAL_PATH>".to_owned()
            } else {
                part.to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn looks_like_windows_path(value: &str) -> bool {
    let trimmed = value.trim_matches(|ch: char| {
        matches!(
            ch,
            '"' | '\'' | '`' | ',' | ';' | ':' | ')' | '(' | '[' | ']' | '{' | '}'
        )
    });
    let bytes = trimmed.as_bytes();
    bytes.len() >= 3
        && bytes[0].is_ascii_alphabetic()
        && bytes[1] == b':'
        && matches!(bytes[2], b'\\' | b'/')
}

fn conversation_detail_json(
    conversation_id: Option<&str>,
    detail: Option<Value>,
) -> Option<String> {
    let conversation_id = conversation_id
        .map(str::trim)
        .filter(|value| !value.is_empty());
    if conversation_id.is_none() && detail.is_none() {
        return None;
    }
    let mut value = detail.unwrap_or_else(|| json!({}));
    if let Some(conversation_id) = conversation_id {
        if let Some(obj) = value.as_object_mut() {
            obj.insert("conversationId".to_owned(), json!(conversation_id));
        } else {
            value = json!({
                "conversationId": conversation_id,
                "detail": value,
            });
        }
    }
    Some(value.to_string())
}

fn parse_detail_json_value(raw: &str) -> Option<Value> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }
    serde_json::from_str::<Value>(trimmed).ok()
}

fn handle_cancel(req: AgentCancelRequest) -> Result<Value> {
    let mut cancelled = false;
    if let Some(token) = req
        .token
        .as_deref()
        .filter(|token| !token.trim().is_empty())
    {
        if let Some(pending) = PENDING.lock().unwrap().remove(token) {
            upsert_task(
                &pending.request_id,
                &pending.target.id,
                "cancelled",
                "Pending confirmation was cancelled.",
                "read-only",
                None,
                "",
                None,
                None,
                None,
            );
            cancelled = true;
        }
    }
    if let Some(request_id) = req
        .request_id
        .as_deref()
        .filter(|request_id| !request_id.trim().is_empty())
    {
        if mark_task_cancel_requested(request_id) {
            cancelled = true;
        }
    }
    if !cancelled {
        bail!("No matching pending or running task to cancel")
    }
    Ok(json!({ "status": "cancelled" }))
}

fn handle_sessions() -> Result<Vec<CodexSessionSummary>> {
    load_codex_session_index()
}

fn handle_session_detail(session_id: &str) -> Result<CodexSessionDetail> {
    load_codex_session_detail(session_id, None, 200)
}

fn handle_session_page(session_id: &str, query: Option<&str>) -> Result<CodexSessionDetail> {
    let cursor = query
        .and_then(parse_query_map)
        .and_then(|params| params.get("cursor").cloned())
        .and_then(|value| value.parse::<usize>().ok());
    let page_size = query
        .and_then(parse_query_map)
        .and_then(|params| params.get("page_size").cloned())
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(200);
    load_codex_session_detail(session_id, cursor, page_size)
}

fn handle_list_skills() -> Result<Vec<SkillCatalogEntry>> {
    Ok(merge_discovered_codex_skills(load_skill_catalog()?.skills))
}

fn handle_upsert_skill(req: SkillCatalogUpsert) -> Result<SkillCatalogEntry> {
    if req.id.trim().is_empty() {
        bail!("Skill id is required");
    }
    let mut catalog = load_skill_catalog()?;
    let now = unix_millis();
    let normalized_id = req.id.trim().to_owned();
    let existing = catalog
        .skills
        .iter()
        .position(|item| item.id == normalized_id);
    let entry = if let Some(index) = existing {
        let current = catalog.skills[index].clone();
        let updated = SkillCatalogEntry {
            id: current.id.clone(),
            title: req.title.unwrap_or(current.title),
            group: req.group.unwrap_or(current.group),
            description: req.description.unwrap_or(current.description),
            enabled: req.enabled.unwrap_or(current.enabled),
            mirror_name: req.mirror_name.unwrap_or(current.mirror_name),
            tags: req.tags.unwrap_or(current.tags),
            updated_at: now,
        };
        catalog.skills[index] = updated.clone();
        updated
    } else {
        let mirror_name = req
            .mirror_name
            .clone()
            .unwrap_or_else(|| normalized_id.replace(' ', "-"));
        let created = SkillCatalogEntry {
            id: normalized_id.clone(),
            title: req.title.unwrap_or_else(|| normalized_id.clone()),
            group: req.group.unwrap_or_else(|| "custom".to_owned()),
            description: req.description.unwrap_or_default(),
            enabled: req.enabled.unwrap_or(true),
            mirror_name,
            tags: req.tags.unwrap_or_default(),
            updated_at: now,
        };
        catalog.skills.push(created.clone());
        created
    };
    save_skill_catalog(&catalog)?;
    if let Some(content) = req.content.as_deref() {
        save_skill_body(&entry, content)?;
    } else if skill_body_file(&entry)
        .parent()
        .map(Path::exists)
        .unwrap_or(false)
    {
    } else {
        save_skill_body(&entry, "# Skill\n")?;
    }
    sync_skill_entry(&entry)?;
    Ok(entry)
}

fn handle_delete_skill(skill_id: &str) -> Result<Value> {
    let normalized_id = skill_id.trim();
    if normalized_id.is_empty() {
        bail!("Skill id is required");
    }
    let mut catalog = load_skill_catalog()?;
    let Some(index) = catalog
        .skills
        .iter()
        .position(|item| item.id == normalized_id)
    else {
        bail!("Unknown skill `{normalized_id}`");
    };
    let removed = catalog.skills.remove(index);
    save_skill_catalog(&catalog)?;
    remove_skill_storage(&removed)?;
    Ok(json!({ "status": "deleted", "id": removed.id }))
}

fn handle_sync_skills() -> Result<Value> {
    let catalog = load_skill_catalog()?;
    let mut synced = 0;
    let mut errors = Vec::new();
    for skill in &catalog.skills {
        match sync_skill_entry(skill) {
            Ok(()) => synced += 1,
            Err(err) => errors.push(format!("{}: {}", skill.id, err)),
        }
    }
    Ok(json!({
        "status": if errors.is_empty() { "ok" } else { "partial" },
        "synced": synced,
        "errors": errors,
    }))
}

fn handle_voice_transcribe(req: VoiceEnvelope) -> Result<Value> {
    let audio = materialize_voice_audio(&req)?;
    let transcript =
        if let Some(text) = run_whisper_transcribe(audio.as_path(), req.language.as_deref())? {
            text
        } else {
            String::new()
        };
    Ok(json!({
        "status": if transcript.is_empty() { "not_configured" } else { "ok" },
        "audioPath": audio.display().to_string(),
        "transcript": transcript,
    }))
}

fn handle_voice_run(req: AgentEnvelope) -> Result<AgentResponse> {
    let route = req.route.unwrap_or_default();
    let voice = req.voice.unwrap_or_default();
    let project = route
        .project_id
        .clone()
        .or_else(|| route.project_path.clone())
        .unwrap_or_default();
    let transcribe = handle_voice_transcribe(voice.clone())?;
    let transcript = transcribe
        .get("transcript")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_owned();
    let prompt = voice
        .normalized_prompt
        .or(req.prompt)
        .unwrap_or_else(|| transcript.clone());
    let request_id = req
        .conversation_id
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
    let detail_json = json!({
        "kind": "voice",
        "transcript": transcript,
        "route": route,
        "voice": transcribe,
    })
    .to_string();
    if prompt.trim().is_empty() {
        return Ok(AgentResponse {
            request_id,
            project,
            status: "failed".to_owned(),
            text: "Voice transcript is empty.".to_owned(),
            token: None,
            detail_json: Some(detail_json),
        });
    }
    let response = handle_run(AgentRunRequest {
        request_id,
        project,
        prompt,
        mode: Some("read-only".to_owned()),
        require_confirmation: Some(true),
        executor: None,
        profile: route.profile_id,
        session: route.codex_thread_id.or(route.active_thread_id),
        resume_last: Some(matches!(route.thread_mode.as_deref(), Some("continue"))),
    })?;
    Ok(AgentResponse {
        detail_json: Some(detail_json),
        ..response
    })
}

fn run_codex(
    request_id: String,
    project: ProjectConfig,
    prompt: String,
    sandbox: &str,
    conversation_id: Option<&str>,
) -> Result<AgentResponse> {
    let project_path = PathBuf::from(&project.path);
    if !project_path.is_dir() {
        bail!("Project path does not exist: {}", project.path);
    }
    let session_index_before = load_codex_session_index().unwrap_or_default();
    upsert_task(
        &request_id,
        &project.id,
        "running",
        "Codex is running.",
        sandbox,
        None,
        "",
        None,
        conversation_detail_json(
            conversation_id,
            Some(json!({
                "kind": "run",
                "projectPath": project.path,
                "sandbox": sandbox,
                "profile": project.profile,
                "session": project.session,
                "resumeLast": project.resume_last,
            })),
        ),
        Some(json!({
            "prompt": prompt,
        })),
    );

    let output_file = temp_output_file(&request_id);
    let output = run_codex_process(&request_id, &project, sandbox, &output_file, &prompt)
        .context("Failed to run codex exec")?;

    if task_cancel_requested(&request_id) {
        upsert_task(
            &request_id,
            &project.id,
            "cancelled",
            "Codex task was cancelled.",
            sandbox,
            None,
            "",
            None,
            None,
            Some(json!({
                "event": "cancelled",
                "sandbox": sandbox,
            })),
        );
        append_audit(&json!({
            "event": "codex_cancelled",
            "request_id": &request_id,
            "project": &project.id,
            "project_path": &project.path,
            "executor": project.executor.clone().unwrap_or_else(|| "codex".to_owned()),
            "profile": &project.profile,
            "session": &project.session,
            "resume_last": project.resume_last,
            "mode": if sandbox == "workspace-write" { "write" } else { "read" },
            "sandbox": sandbox,
            "prompt": &prompt,
        }));
        return Ok(AgentResponse {
            request_id,
            project: project.id,
            status: "cancelled".to_owned(),
            text: "Codex task was cancelled.".to_owned(),
            token: None,
            detail_json: None,
        });
    }

    let exit_code = output.status.code().unwrap_or(-1);
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let final_text = fs::read_to_string(&output_file)
        .ok()
        .filter(|text| !text.trim().is_empty())
        .or_else(|| extract_codex_final_text(&stdout))
        .unwrap_or_else(|| stdout.clone());
    let text = if output.status.success() {
        truncate_text(&final_text)
    } else {
        truncate_text(&format!(
            "codex exited with {exit_code}\n{stderr}\n{stdout}"
        ))
    };
    let error = if output.status.success() {
        String::new()
    } else {
        truncate_text(&stderr)
    };
    let status = if output.status.success() {
        "done"
    } else {
        "failed"
    };
    let resolved_session_id = extract_codex_thread_id(&stdout)
        .or_else(|| resolve_result_session_id(&project, &session_index_before));
    upsert_task(
        &request_id,
        &project.id,
        status,
        &text,
        sandbox,
        Some(exit_code),
        &error,
        None,
        conversation_detail_json(
            conversation_id,
            Some(json!({
                "kind": "codexResult",
                "stdout": truncate_text(&stdout),
                "stderr": truncate_text(&stderr),
                "exitCode": exit_code,
                "sandbox": sandbox,
                "sessionId": resolved_session_id,
            })),
        ),
        Some(json!({
            "event": "codex_exec",
            "outputFile": output_file.display().to_string(),
        })),
    );

    append_audit(&json!({
        "event": "codex_exec",
        "request_id": &request_id,
        "project": &project.id,
        "project_path": &project.path,
        "executor": project.executor.clone().unwrap_or_else(|| "codex".to_owned()),
        "profile": &project.profile,
        "session": &project.session,
        "resume_last": project.resume_last,
        "mode": if sandbox == "workspace-write" { "write" } else { "read" },
        "sandbox": sandbox,
        "exit_code": exit_code,
        "session_id": resolved_session_id,
        "prompt": &prompt,
        "output_file": output_file.display().to_string(),
        "summary": &text,
        "error": &error,
    }));

    Ok(AgentResponse {
        request_id,
        project: project.id,
        status: status.to_owned(),
        text,
        token: None,
        detail_json: conversation_detail_json(
            conversation_id,
            Some(json!({
                "kind": "codexResult",
                "exitCode": exit_code,
                "sandbox": sandbox,
                "error": error,
                "sessionId": resolved_session_id,
            })),
        ),
    })
}

fn resolve_result_session_id(
    project: &ProjectConfig,
    session_index_before: &[CodexSessionSummary],
) -> Option<String> {
    if let Some(session_id) = project
        .session
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        return Some(session_id.to_owned());
    }
    let session_index_after = load_codex_session_index().ok()?;
    if project.resume_last {
        return session_index_after.first().map(|item| item.id.clone());
    }
    let existing_ids: HashSet<&str> = session_index_before
        .iter()
        .map(|item| item.id.as_str())
        .collect();
    session_index_after
        .iter()
        .find(|item| !existing_ids.contains(item.id.as_str()))
        .map(|item| item.id.clone())
}

fn extract_codex_thread_id(stdout: &str) -> Option<String> {
    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let Ok(value) = serde_json::from_str::<Value>(trimmed) else {
            continue;
        };
        let event_type = value
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or_default();
        if event_type != "thread.started" {
            continue;
        }
        let thread_id = value
            .get("thread_id")
            .or_else(|| value.get("threadId"))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())?;
        return Some(thread_id.to_owned());
    }
    None
}

fn extract_codex_final_text(stdout: &str) -> Option<String> {
    let mut latest = None;
    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let Ok(value) = serde_json::from_str::<Value>(trimmed) else {
            continue;
        };
        let item = value.get("item")?;
        let item_type = item.get("type").and_then(Value::as_str).unwrap_or_default();
        if item_type != "agent_message" {
            continue;
        }
        let text = item
            .get("text")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())?;
        latest = Some(text.to_owned());
    }
    latest
}

fn run_codex_process(
    request_id: &str,
    project: &ProjectConfig,
    sandbox: &str,
    output_file: &Path,
    prompt: &str,
) -> Result<Output> {
    let executor = project.executor.as_deref().unwrap_or("codex");
    if !executor.eq_ignore_ascii_case("codex") {
        bail!(
            "Executor `{}` is not supported yet. Direct Codex routing is currently available.",
            executor
        );
    }
    let codex_command = resolved_codex_command();
    #[cfg(windows)]
    let mut command = {
        let trimmed = codex_command.trim();
        if trimmed.to_ascii_lowercase().ends_with(".cmd") {
            let mut command = Command::new("cmd.exe");
            command.arg("/c").arg(trimmed);
            command
        } else {
            Command::new(trimmed)
        }
    };
    #[cfg(not(windows))]
    let mut command = Command::new(codex_command.trim());
    command
        .arg("exec")
        .arg("--json")
        .arg("--cd")
        .arg(&project.path)
        .arg("--sandbox")
        .arg(sandbox)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if !path_has_git_marker(Path::new(&project.path)) {
        command.arg("--skip-git-repo-check");
    }
    #[cfg(windows)]
    command.creation_flags(CREATE_NO_WINDOW);
    if let Some(profile) = project
        .profile
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        command.arg("--profile").arg(profile);
    }
    let session = project
        .session
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    if project.resume_last || session.is_some() {
        command.arg("resume");
        if project.resume_last {
            command.arg("--last");
        } else if let Some(session) = session {
            command.arg(session);
        }
        command
            .arg("--output-last-message")
            .arg(output_file)
            .arg("-");
    } else {
        command
            .arg("--output-last-message")
            .arg(output_file)
            .arg("-");
    }
    let mut child = command.spawn().context("Failed to spawn codex exec")?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(prompt.as_bytes())
            .context("Failed to write Codex prompt to stdin")?;
    }
    loop {
        if task_cancel_requested(request_id) {
            let _ = child.kill();
            return child
                .wait_with_output()
                .context("Failed to collect cancelled codex output");
        }
        if child.try_wait()?.is_some() {
            return child
                .wait_with_output()
                .context("Failed to collect codex output");
        }
        std::thread::sleep(std::time::Duration::from_millis(250));
    }
}

fn path_has_git_marker(path: &Path) -> bool {
    path.ancestors()
        .any(|ancestor| ancestor.join(".git").exists())
}

fn temp_output_file(request_id: &str) -> PathBuf {
    std::env::temp_dir().join(format!("rustdesk-codex-{request_id}.txt"))
}

fn upsert_task(
    request_id: &str,
    project: &str,
    status: &str,
    text: &str,
    sandbox: &str,
    exit_code: Option<i32>,
    error: &str,
    token: Option<String>,
    detail_json: Option<String>,
    raw_event: Option<Value>,
) {
    let now = unix_millis();
    let text = truncate_text(text);
    let error = truncate_text(error);
    let timeline_event = AgentTimelineEvent {
        stage: status.to_owned(),
        summary: text.clone(),
        ts: now,
        raw: raw_event.clone(),
    };
    let mut tasks = TASKS.lock().unwrap();
    match tasks.entry(request_id.to_owned()) {
        Entry::Occupied(mut entry) => {
            let task = entry.get_mut();
            task.project = project.to_owned();
            task.status = status.to_owned();
            task.text = text;
            task.sandbox = sandbox.to_owned();
            task.updated_at = now;
            task.exit_code = exit_code;
            task.error = error;
            task.token = token;
            if let Some(detail_json) = detail_json {
                task.detail_json = detail_json;
            }
            if task.timeline.len() >= MAX_TASK_TIMELINE {
                task.timeline.remove(0);
            }
            task.timeline.push(timeline_event);
            if let Some(event) = raw_event {
                if task.raw_events.len() >= MAX_TASK_RAW_EVENTS {
                    task.raw_events.remove(0);
                }
                task.raw_events.push(event);
            }
        }
        Entry::Vacant(entry) => {
            let mut timeline = Vec::with_capacity(1);
            timeline.push(timeline_event);
            let mut raw_events = Vec::new();
            if let Some(event) = raw_event {
                raw_events.push(event);
            }
            entry.insert(AgentTaskInfo {
                request_id: request_id.to_owned(),
                project: project.to_owned(),
                status: status.to_owned(),
                text,
                sandbox: sandbox.to_owned(),
                started_at: now,
                updated_at: now,
                exit_code,
                error,
                token,
                cancel_requested: false,
                detail_json: detail_json.unwrap_or_default(),
                timeline,
                raw_events,
            });
        }
    }
}

fn mark_task_cancel_requested(request_id: &str) -> bool {
    let mut tasks = TASKS.lock().unwrap();
    let Some(task) = tasks.get_mut(request_id) else {
        return false;
    };
    task.cancel_requested = true;
    task.updated_at = unix_millis();
    if task.status == "needs_confirmation" {
        task.status = "cancelled".to_owned();
        task.text = "Pending confirmation was cancelled.".to_owned();
        task.token = None;
    }
    if task.timeline.len() >= MAX_TASK_TIMELINE {
        task.timeline.remove(0);
    }
    task.timeline.push(AgentTimelineEvent {
        stage: "cancelled".to_owned(),
        summary: task.text.clone(),
        ts: task.updated_at,
        raw: None,
    });
    true
}

fn task_cancel_requested(request_id: &str) -> bool {
    TASKS
        .lock()
        .unwrap()
        .get(request_id)
        .map(|task| task.cancel_requested)
        .unwrap_or(false)
}

fn looks_like_write_request(prompt: &str) -> bool {
    let current_request = prompt
        .rsplit_once("Current request:\n")
        .map(|(_, current)| current)
        .unwrap_or(prompt);
    let prompt = current_request.to_lowercase();
    [
        "modify",
        "change",
        "edit",
        "write",
        "implement",
        "fix",
        "delete",
        "remove",
        "commit",
        "修改",
        "实现",
        "修复",
        "删除",
        "移除",
        "提交",
        "写入",
        "新增",
        "创建",
    ]
    .iter()
    .any(|word| prompt.contains(word))
}

fn new_token() -> String {
    format!(
        "{}-{}",
        unix_millis(),
        uuid::Uuid::new_v4()
            .to_string()
            .split('-')
            .next()
            .unwrap_or("token")
    )
}

fn unix_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

fn parse_query_map(query: &str) -> Option<HashMap<String, String>> {
    let mut map = HashMap::new();
    for pair in query.split('&') {
        let Some((key, value)) = pair.split_once('=') else {
            continue;
        };
        map.insert(key.to_owned(), value.to_owned());
    }
    Some(map)
}

fn truncate_text(text: &str) -> String {
    if text.len() <= MAX_RESPONSE_TEXT {
        text.to_owned()
    } else {
        let mut end = MAX_RESPONSE_TEXT;
        while !text.is_char_boundary(end) {
            end -= 1;
        }
        format!("{}\n...[truncated]", &text[..end])
    }
}

fn audit_file() -> PathBuf {
    let base = Config::file()
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_else(std::env::temp_dir);
    base.join("codex-bridge-audit.jsonl")
}

fn bridge_data_dir() -> PathBuf {
    Config::path("agent-dashboard")
}

fn session_index_file() -> PathBuf {
    codex_home_dir().join("session_index.jsonl")
}

fn codex_home_dir() -> PathBuf {
    std::env::var_os("CODEX_HOME")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("USERPROFILE").map(|value| PathBuf::from(value).join(".codex"))
        })
        .or_else(|| {
            let drive = std::env::var_os("HOMEDRIVE")?;
            let path = std::env::var_os("HOMEPATH")?;
            Some(
                PathBuf::from(format!(
                    "{}{}",
                    drive.to_string_lossy(),
                    path.to_string_lossy()
                ))
                .join(".codex"),
            )
        })
        .unwrap_or_else(|| Config::get_home().join(".codex"))
}

fn codex_sessions_dir() -> PathBuf {
    codex_home_dir().join("sessions")
}

fn rustdesk_skill_dir() -> PathBuf {
    bridge_data_dir().join("skills")
}

fn rustdesk_skill_catalog_file() -> PathBuf {
    rustdesk_skill_dir().join("catalog.json")
}

fn codex_skills_dir() -> PathBuf {
    codex_home_dir().join("skills")
}

fn merge_discovered_codex_skills(
    mut catalog_skills: Vec<SkillCatalogEntry>,
) -> Vec<SkillCatalogEntry> {
    let mut seen_ids: HashSet<String> = catalog_skills
        .iter()
        .map(|entry| entry.id.clone())
        .collect();
    let mut seen_mirror_names: HashSet<String> = catalog_skills
        .iter()
        .map(|entry| entry.mirror_name.clone())
        .collect();
    for discovered in discover_codex_skill_entries() {
        if seen_ids.contains(&discovered.id) || seen_mirror_names.contains(&discovered.id) {
            continue;
        }
        seen_ids.insert(discovered.id.clone());
        seen_mirror_names.insert(discovered.mirror_name.clone());
        catalog_skills.push(discovered);
    }
    catalog_skills.sort_by(|a, b| {
        b.updated_at
            .cmp(&a.updated_at)
            .then_with(|| a.id.cmp(&b.id))
    });
    catalog_skills
}

fn discover_codex_skill_entries() -> Vec<SkillCatalogEntry> {
    let skills_dir = codex_skills_dir();
    let mut entries = discover_codex_skill_entries_in_dir(&skills_dir, "local", Some(".system"));
    entries.extend(discover_codex_skill_entries_in_dir(
        &skills_dir.join(".system"),
        "system",
        None,
    ));
    entries
}

fn discover_codex_skill_entries_in_dir(
    root: &Path,
    group: &str,
    skip_dir_name: Option<&str>,
) -> Vec<SkillCatalogEntry> {
    let Ok(entries) = fs::read_dir(root) else {
        return Vec::new();
    };
    let mut discovered = Vec::new();
    for entry in entries.flatten() {
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if !file_type.is_dir() {
            continue;
        }
        let file_name = entry.file_name().to_string_lossy().trim().to_owned();
        if file_name.is_empty() {
            continue;
        }
        if skip_dir_name.is_some_and(|skip| file_name == skip) {
            continue;
        }
        let skill_file = entry.path().join("SKILL.md");
        if !skill_file.is_file() {
            continue;
        }
        discovered.push(discovered_skill_entry(&file_name, group, &skill_file));
    }
    discovered
}

fn discovered_skill_entry(id: &str, group: &str, skill_file: &Path) -> SkillCatalogEntry {
    let (title, description) = read_skill_metadata(skill_file);
    SkillCatalogEntry {
        id: id.to_owned(),
        title: title.unwrap_or_else(|| id.to_owned()),
        group: group.to_owned(),
        description: description.unwrap_or_default(),
        enabled: true,
        mirror_name: id.to_owned(),
        tags: Vec::new(),
        updated_at: skill_file
            .metadata()
            .ok()
            .and_then(|metadata| metadata.modified().ok())
            .map(system_time_to_unix_millis)
            .unwrap_or_default(),
    }
}

fn read_skill_metadata(skill_file: &Path) -> (Option<String>, Option<String>) {
    let Ok(raw) = fs::read_to_string(skill_file) else {
        return (None, None);
    };
    let (name, description) = parse_skill_front_matter(&raw);
    (
        normalize_skill_metadata_value(name),
        normalize_skill_metadata_value(description),
    )
}

fn parse_skill_front_matter(raw: &str) -> (Option<String>, Option<String>) {
    let mut lines = raw.lines();
    if lines.next().map(str::trim) != Some("---") {
        return (None, None);
    }
    let mut name = None;
    let mut description = None;
    for line in lines {
        let trimmed = line.trim();
        if trimmed == "---" {
            break;
        }
        let Some((key, value)) = trimmed.split_once(':') else {
            continue;
        };
        let parsed_value = strip_wrapping_quotes(value.trim()).to_owned();
        match key.trim() {
            "name" => name = Some(parsed_value),
            "description" => description = Some(parsed_value),
            _ => {}
        }
    }
    (name, description)
}

fn normalize_skill_metadata_value(value: Option<String>) -> Option<String> {
    value.and_then(|item| {
        let trimmed = item.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_owned())
        }
    })
}

fn strip_wrapping_quotes(value: &str) -> &str {
    if value.len() >= 2 {
        let bytes = value.as_bytes();
        let first = bytes[0];
        let last = bytes[value.len() - 1];
        if (first == b'"' && last == b'"') || (first == b'\'' && last == b'\'') {
            return &value[1..value.len() - 1];
        }
    }
    value
}

fn system_time_to_unix_millis(time: SystemTime) -> u128 {
    time.duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or_default()
}

fn whisper_command(project: Option<&ProjectConfig>) -> String {
    if let Some(project) = project {
        if let Some(command) = project
            .whisper_command
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            return command.to_owned();
        }
    }
    let command = Config::get_option(WHISPER_COMMAND);
    if command.trim().is_empty() {
        "whisper-cli".to_owned()
    } else {
        command
    }
}

fn whisper_model(project: Option<&ProjectConfig>) -> String {
    if let Some(project) = project {
        if let Some(model) = project
            .whisper_model
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            return model.to_owned();
        }
    }
    Config::get_option(WHISPER_MODEL)
}

fn load_codex_session_index() -> Result<Vec<CodexSessionSummary>> {
    let index_file = session_index_file();
    if !index_file.exists() {
        clear_codex_session_index_cache();
        return Ok(Vec::new());
    }
    let metadata = fs::metadata(&index_file)
        .with_context(|| format!("Failed to stat {}", index_file.display()))?;
    let modified_at = metadata.modified().ok();
    let len = metadata.len();
    if let Some(cached) = cached_codex_session_index(&index_file, modified_at, len) {
        return Ok(cached);
    }
    let raw = fs::read_to_string(&index_file)
        .with_context(|| format!("Failed to read {}", index_file.display()))?;
    let sessions = parse_codex_session_index(&raw);
    store_codex_session_index_cache(&index_file, modified_at, len, &sessions);
    Ok(sessions)
}

fn load_codex_session_detail(
    session_id: &str,
    cursor: Option<usize>,
    page_size: usize,
) -> Result<CodexSessionDetail> {
    let session_path = find_session_file_cached(session_id)
        .ok_or_else(|| anyhow!("Session file not found for `{session_id}`"))?;
    let session = load_codex_session_index()
        .unwrap_or_default()
        .into_iter()
        .find(|item| item.id == session_id);
    let projects = load_projects().unwrap_or_default();
    let fallback_metadata =
        read_session_project_metadata(&session_path, &projects).unwrap_or_default();
    let line_index = load_session_line_index(&session_path)?;
    let line_count = line_index.lines.len();
    let take = page_size.max(1);
    let end = cursor.unwrap_or(line_count).min(line_count);
    let start = end.saturating_sub(take);
    let chunk = read_session_lines(&session_path, &line_index.lines[start..end])?;
    let mut messages = Vec::new();
    let mut timeline = Vec::new();
    let mut raw_events = Vec::new();
    for line in chunk {
        let Ok(value) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        if raw_events.len() < MAX_TASK_RAW_EVENTS {
            raw_events.push(value.clone());
        }
        let timestamp = value
            .get("timestamp")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned();
        match value
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or_default()
        {
            "response_item" => {
                if let Some(payload) = value.get("payload") {
                    let role = payload
                        .get("role")
                        .and_then(Value::as_str)
                        .or_else(|| {
                            payload
                                .get("message")
                                .and_then(|message| message.get("role"))
                                .and_then(Value::as_str)
                        })
                        .unwrap_or("assistant")
                        .to_owned();
                    if matches!(role.as_str(), "developer" | "system") {
                        continue;
                    }
                    let text = extract_payload_text(payload);
                    if !text.trim().is_empty() {
                        messages.push(CodexSessionMessage {
                            role,
                            text: text.trim().to_owned(),
                            timestamp: timestamp.clone(),
                        });
                    }
                }
            }
            "event_msg" => {
                let summary = value
                    .get("payload")
                    .and_then(|payload| payload.get("message"))
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                if !summary.trim().is_empty() && timeline.len() < MAX_TASK_TIMELINE {
                    timeline.push(AgentTimelineEvent {
                        stage: value
                            .get("payload")
                            .and_then(|payload| payload.get("type"))
                            .and_then(Value::as_str)
                            .unwrap_or("event")
                            .to_owned(),
                        summary: truncate_text(summary.trim()),
                        ts: unix_millis(),
                        raw: Some(value.clone()),
                    });
                }
            }
            _ => {}
        }
    }
    let next_cursor = if start > 0 { Some(start) } else { None };
    Ok(CodexSessionDetail {
        id: session
            .as_ref()
            .map(|item| item.id.clone())
            .unwrap_or_else(|| session_id.to_owned()),
        title: session
            .as_ref()
            .map(|item| decode_lossy_utf8(&item.title))
            .filter(|title| !title.trim().is_empty())
            .unwrap_or_else(|| session_id.to_owned()),
        updated_at: session
            .as_ref()
            .map(|item| item.updated_at.clone())
            .unwrap_or_default(),
        project_id: session
            .as_ref()
            .map(|item| item.project_id.clone())
            .filter(|project_id| !project_id.trim().is_empty())
            .unwrap_or(fallback_metadata.project_id),
        project_path: session
            .as_ref()
            .map(|item| item.project_path.clone())
            .filter(|project_path| !project_path.trim().is_empty())
            .unwrap_or(fallback_metadata.project_path),
        messages,
        timeline,
        raw_events,
        next_cursor,
    })
}

fn extract_payload_text(payload: &Value) -> String {
    if let Some(message) = payload.get("message") {
        let nested = extract_payload_text(message);
        if !nested.trim().is_empty() {
            return nested;
        }
    }
    if let Some(content) = payload.get("content").and_then(Value::as_array) {
        let mut out = Vec::new();
        for item in content {
            if let Some(text) = item.get("text").and_then(Value::as_str) {
                out.push(text.to_owned());
            }
        }
        return out.join("\n");
    }
    payload
        .get("text")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned()
}

fn decode_lossy_utf8(value: &str) -> String {
    value.to_owned()
}

fn parse_codex_session_index(raw: &str) -> Vec<CodexSessionSummary> {
    let mut sessions = Vec::new();
    for line in raw.lines() {
        if line.trim().is_empty() {
            continue;
        }
        if let Ok(mut item) = serde_json::from_str::<CodexSessionSummary>(line) {
            if item.title.trim().is_empty() {
                item.title = item.id.clone();
            }
            sessions.push(item);
        }
    }
    enrich_session_summaries_with_project_metadata(&mut sessions);
    sessions.sort_by(|a, b| {
        b.updated_at
            .cmp(&a.updated_at)
            .then_with(|| a.id.cmp(&b.id))
    });
    sessions
}

fn enrich_session_summaries_with_project_metadata(sessions: &mut [CodexSessionSummary]) {
    let projects = load_projects().unwrap_or_default();
    for session in sessions {
        let Some(session_path) = find_session_file_cached(&session.id) else {
            continue;
        };
        match read_session_project_metadata(&session_path, &projects) {
            Ok(metadata) => {
                if !metadata.project_id.trim().is_empty() {
                    session.project_id = metadata.project_id;
                }
                if !metadata.project_path.trim().is_empty() {
                    session.project_path = metadata.project_path;
                }
            }
            Err(err) => {
                log::warn!(
                    "failed to read project metadata for Codex session {}: {}",
                    session.id,
                    err
                );
            }
        }
    }
}

#[derive(Debug, Clone, Default)]
struct CodexSessionProjectMetadata {
    project_id: String,
    project_path: String,
}

fn read_session_project_metadata(
    path: &Path,
    projects: &[ProjectConfig],
) -> Result<CodexSessionProjectMetadata> {
    let file =
        fs::File::open(path).with_context(|| format!("Failed to open {}", path.display()))?;
    let reader = BufReader::new(file);
    for line in reader.lines().take(24) {
        let line = line.with_context(|| format!("Failed to read {}", path.display()))?;
        if line.trim().is_empty() {
            continue;
        }
        let Ok(value) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        if value
            .get("type")
            .and_then(Value::as_str)
            .map(|kind| kind == "session_meta")
            .unwrap_or(false)
        {
            let cwd = value
                .get("payload")
                .and_then(|payload| payload.get("cwd"))
                .and_then(Value::as_str)
                .unwrap_or_default()
                .trim();
            if !cwd.is_empty() {
                return Ok(metadata_from_project_path(cwd, projects));
            }
        }
        if let Some(path) = value
            .get("project_path")
            .or_else(|| value.get("projectPath"))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            return Ok(metadata_from_project_path(path, projects));
        }
    }
    Ok(CodexSessionProjectMetadata::default())
}

fn metadata_from_project_path(
    path: &str,
    projects: &[ProjectConfig],
) -> CodexSessionProjectMetadata {
    let normalized_path = normalize_session_project_path(path);
    let project_id = projects
        .iter()
        .find(|project| paths_refer_to_same_location(&project.path, &normalized_path))
        .map(|project| project.id.clone())
        .unwrap_or_else(|| project_id_from_path(&normalized_path));
    CodexSessionProjectMetadata {
        project_id,
        project_path: normalized_path,
    }
}

fn normalize_session_project_path(path: &str) -> String {
    path.trim()
        .trim_start_matches(r"\\?\")
        .trim_end_matches(['\\', '/'])
        .to_owned()
}

fn paths_refer_to_same_location(left: &str, right: &str) -> bool {
    normalize_session_project_path(left)
        .eq_ignore_ascii_case(&normalize_session_project_path(right))
}

fn project_id_from_path(path: &str) -> String {
    Path::new(path)
        .file_name()
        .and_then(|value| value.to_str())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("unknown")
        .to_owned()
}

fn cached_codex_session_index(
    path: &Path,
    modified_at: Option<SystemTime>,
    len: u64,
) -> Option<Vec<CodexSessionSummary>> {
    let cache = SESSION_INDEX_CACHE.lock().unwrap();
    let cached = cache.as_ref()?;
    if cached.path != path {
        return None;
    }
    if cached.len != len || cached.modified_at != modified_at {
        return None;
    }
    Some(cached.sessions.clone())
}

fn store_codex_session_index_cache(
    path: &Path,
    modified_at: Option<SystemTime>,
    len: u64,
    sessions: &[CodexSessionSummary],
) {
    let mut cache = SESSION_INDEX_CACHE.lock().unwrap();
    *cache = Some(CodexSessionIndexCache {
        path: path.to_path_buf(),
        modified_at,
        len,
        sessions: sessions.to_vec(),
    });
}

fn clear_codex_session_index_cache() {
    let mut cache = SESSION_INDEX_CACHE.lock().unwrap();
    *cache = None;
}

fn load_session_line_index(path: &Path) -> Result<CodexSessionLineIndexCache> {
    let metadata =
        fs::metadata(path).with_context(|| format!("Failed to stat {}", path.display()))?;
    let modified_at = metadata.modified().ok();
    let len = metadata.len();
    if let Some(cached) = {
        let cache = SESSION_LINE_INDEX_CACHE.lock().unwrap();
        cache.get(path).cloned()
    } {
        if cached.modified_at == modified_at && cached.len == len {
            return Ok(cached);
        }
    }
    let built = build_session_line_index(path, modified_at, len)?;
    SESSION_LINE_INDEX_CACHE
        .lock()
        .unwrap()
        .insert(path.to_path_buf(), built.clone());
    Ok(built)
}

fn build_session_line_index(
    path: &Path,
    modified_at: Option<SystemTime>,
    len: u64,
) -> Result<CodexSessionLineIndexCache> {
    let file =
        fs::File::open(path).with_context(|| format!("Failed to open {}", path.display()))?;
    let mut reader = BufReader::new(file);
    let mut lines = Vec::new();
    let mut offset = 0_u64;
    loop {
        let mut buffer = Vec::new();
        let bytes = reader
            .read_until(b'\n', &mut buffer)
            .with_context(|| format!("Failed to read {}", path.display()))?;
        if bytes == 0 {
            break;
        }
        let line_len = bytes;
        let content_len = trim_line_break_len(&buffer);
        if buffer[..content_len]
            .iter()
            .any(|byte| !byte.is_ascii_whitespace())
        {
            lines.push(CodexSessionLineSpan {
                start: offset,
                len: line_len,
            });
        }
        offset += line_len as u64;
    }
    Ok(CodexSessionLineIndexCache {
        modified_at,
        len,
        lines,
    })
}

fn read_session_lines(path: &Path, spans: &[CodexSessionLineSpan]) -> Result<Vec<String>> {
    let mut file =
        fs::File::open(path).with_context(|| format!("Failed to open {}", path.display()))?;
    let mut lines = Vec::with_capacity(spans.len());
    for span in spans {
        file.seek(SeekFrom::Start(span.start))
            .with_context(|| format!("Failed to seek {}", path.display()))?;
        let mut buffer = vec![0_u8; span.len];
        file.read_exact(&mut buffer)
            .with_context(|| format!("Failed to read {}", path.display()))?;
        let content_len = trim_line_break_len(&buffer);
        let line = String::from_utf8_lossy(&buffer[..content_len]).to_string();
        lines.push(line);
    }
    Ok(lines)
}

fn trim_line_break_len(buffer: &[u8]) -> usize {
    let mut end = buffer.len();
    while end > 0 && matches!(buffer[end - 1], b'\n' | b'\r') {
        end -= 1;
    }
    end
}

fn find_session_file_cached(session_id: &str) -> Option<PathBuf> {
    let cached = {
        let cache = SESSION_FILE_CACHE.lock().unwrap();
        cache.get(session_id).cloned()
    };
    if let Some(cached) = cached {
        if cached.is_file() {
            return Some(cached);
        }
        SESSION_FILE_CACHE.lock().unwrap().remove(session_id);
    }
    let resolved = find_session_file_uncached(session_id)?;
    SESSION_FILE_CACHE
        .lock()
        .unwrap()
        .insert(session_id.to_owned(), resolved.clone());
    Some(resolved)
}

fn find_session_file_uncached(session_id: &str) -> Option<PathBuf> {
    let sessions_dir = codex_sessions_dir();
    if !sessions_dir.is_dir() {
        return None;
    }
    find_file_recursive(&sessions_dir, session_id)
}

fn find_file_recursive(dir: &Path, session_id: &str) -> Option<PathBuf> {
    let Ok(read_dir) = fs::read_dir(dir) else {
        return None;
    };
    for entry in read_dir.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if let Some(found) = find_file_recursive(&path, session_id) {
                return Some(found);
            }
            continue;
        }
        if let Some(stem) = path.file_stem().and_then(|name| name.to_str()) {
            if stem == session_id || stem.contains(session_id) {
                return Some(path);
            }
        }
    }
    None
}

fn load_skill_catalog() -> Result<SkillCatalogFile> {
    let file = rustdesk_skill_catalog_file();
    if !file.exists() {
        return Ok(SkillCatalogFile { skills: Vec::new() });
    }
    let raw =
        fs::read_to_string(&file).with_context(|| format!("Failed to read {}", file.display()))?;
    serde_json::from_str(&raw).context("Invalid RustDesk skill catalog")
}

fn save_skill_catalog(catalog: &SkillCatalogFile) -> Result<()> {
    let file = rustdesk_skill_catalog_file();
    if let Some(parent) = file.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create {}", parent.display()))?;
    }
    let encoded = serde_json::to_string_pretty(catalog)?;
    fs::write(&file, encoded).with_context(|| format!("Failed to write {}", file.display()))
}

fn skill_entry_dir(entry: &SkillCatalogEntry) -> PathBuf {
    rustdesk_skill_dir().join(&entry.id)
}

fn skill_body_file(entry: &SkillCatalogEntry) -> PathBuf {
    skill_entry_dir(entry).join("SKILL.md")
}

fn save_skill_body(entry: &SkillCatalogEntry, content: &str) -> Result<()> {
    let file = skill_body_file(entry);
    if let Some(parent) = file.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create {}", parent.display()))?;
    }
    fs::write(&file, content).with_context(|| format!("Failed to write {}", file.display()))
}

fn sync_skill_entry(entry: &SkillCatalogEntry) -> Result<()> {
    let source = skill_body_file(entry);
    if !source.exists() {
        bail!("Skill body is missing: {}", source.display());
    }
    let target_dir = codex_skills_dir().join(&entry.mirror_name);
    fs::create_dir_all(&target_dir)
        .with_context(|| format!("Failed to create {}", target_dir.display()))?;
    let target = target_dir.join("SKILL.md");
    fs::copy(&source, &target)
        .with_context(|| format!("Failed to mirror skill to {}", target.display()))?;
    Ok(())
}

fn remove_skill_storage(entry: &SkillCatalogEntry) -> Result<()> {
    let source_dir = skill_entry_dir(entry);
    if source_dir.exists() {
        fs::remove_dir_all(&source_dir)
            .with_context(|| format!("Failed to remove {}", source_dir.display()))?;
    }
    let target_dir = codex_skills_dir().join(&entry.mirror_name);
    if target_dir.exists() {
        fs::remove_dir_all(&target_dir)
            .with_context(|| format!("Failed to remove {}", target_dir.display()))?;
    }
    Ok(())
}

fn materialize_voice_audio(req: &VoiceEnvelope) -> Result<PathBuf> {
    if let Some(path) = req
        .audio_path
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        let audio = PathBuf::from(path);
        if audio.is_file() {
            return Ok(audio);
        }
        bail!("Audio path does not exist: {path}");
    }
    let audio_base64 = req
        .audio_base64
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("audio_base64 or audio_path is required"))?;
    let decoded = hbb_common::base64::decode(audio_base64).context("Invalid audio_base64")?;
    let file = bridge_data_dir().join(format!("voice-{}.wav", unix_millis()));
    if let Some(parent) = file.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create {}", parent.display()))?;
    }
    cleanup_stale_voice_temp_files(&file);
    fs::write(&file, decoded).with_context(|| format!("Failed to write {}", file.display()))?;
    Ok(file)
}

fn cleanup_stale_voice_temp_files(current_file: &Path) {
    cleanup_stale_voice_temp_files_with_max_age(current_file, std::time::Duration::from_secs(3600));
}

fn cleanup_stale_voice_temp_files_with_max_age(current_file: &Path, max_age: std::time::Duration) {
    let Some(parent) = current_file.parent() else {
        return;
    };
    let Ok(entries) = fs::read_dir(parent) else {
        return;
    };
    let now = SystemTime::now();
    for entry in entries.flatten() {
        let path = entry.path();
        if path == current_file {
            continue;
        }
        let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
            continue;
        };
        if !name.starts_with("voice-") || !name.ends_with(".wav") {
            continue;
        }
        let Ok(metadata) = entry.metadata() else {
            continue;
        };
        let Ok(modified_at) = metadata.modified() else {
            continue;
        };
        let Ok(age) = now.duration_since(modified_at) else {
            continue;
        };
        if age >= max_age {
            let _ = fs::remove_file(path);
        }
    }
}

fn run_whisper_transcribe(audio_path: &Path, language: Option<&str>) -> Result<Option<String>> {
    let command = whisper_command(None);
    let model = whisper_model(None);
    if model.trim().is_empty() {
        return Ok(None);
    }
    let mut child = Command::new(command);
    child
        .arg("-m")
        .arg(model)
        .arg("-f")
        .arg(audio_path)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(windows)]
    child.creation_flags(CREATE_NO_WINDOW);
    if let Some(language) = language.map(str::trim).filter(|value| !value.is_empty()) {
        child.arg("-l").arg(language);
    }
    let output = child.output().context("Failed to run whisper.cpp")?;
    if !output.status.success() {
        return Ok(None);
    }
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let transcript = stdout.lines().last().unwrap_or_default().trim().to_owned();
    if transcript.is_empty() {
        Ok(None)
    } else {
        Ok(Some(transcript))
    }
}

fn append_audit(value: &Value) {
    let mut value = value.clone();
    if let Some(obj) = value.as_object_mut() {
        obj.insert("ts".to_owned(), json!(unix_millis()));
    }
    if let Ok(mut f) = OpenOptions::new()
        .create(true)
        .append(true)
        .open(audit_file())
    {
        let _ = writeln!(f, "{}", value);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Mutex, MutexGuard};

    lazy_static::lazy_static! {
        static ref TEST_ENV_LOCK: Mutex<()> = Default::default();
    }

    struct ConfigOptionGuard {
        key: String,
        previous: String,
    }

    impl ConfigOptionGuard {
        fn replace(key: &str, value: String) -> Self {
            let previous = Config::get_option(key);
            Config::set_option(key.to_owned(), value);
            Self {
                key: key.to_owned(),
                previous,
            }
        }
    }

    impl Drop for ConfigOptionGuard {
        fn drop(&mut self) {
            Config::set_option(self.key.clone(), self.previous.clone());
        }
    }

    fn test_env_lock() -> MutexGuard<'static, ()> {
        TEST_ENV_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    #[test]
    fn parse_codex_session_index_sorts_and_fills_missing_title() {
        let raw = r#"{"id":"session-a","updated_at":"2026-06-05T10:00:00Z","thread_name":""}
{"id":"session-b","updated_at":"2026-06-06T10:00:00Z","thread_name":"B thread"}"#;
        let sessions = parse_codex_session_index(raw);
        assert_eq!(sessions.len(), 2);
        assert_eq!(sessions[0].id, "session-b");
        assert_eq!(sessions[0].title, "B thread");
        assert_eq!(sessions[1].id, "session-a");
        assert_eq!(sessions[1].title, "session-a");
    }

    #[test]
    fn looks_like_write_request_uses_current_request_section_for_dashboard_prompt() {
        let prompt = "Conversation history:\nplease fix the build\n\nCurrent request:\nreply with one short line";
        assert!(!looks_like_write_request(prompt));
        assert!(looks_like_write_request(
            "Conversation history:\nread-only please\n\nCurrent request:\nfix the build"
        ));
    }

    #[test]
    fn compose_envelope_prompt_omits_runtime_info_when_no_context_is_needed() {
        let context = AgentEnvelopeContext {
            runtime_info: Some("rustdesk-dashboard".to_owned()),
            ..Default::default()
        };

        let prompt = compose_envelope_prompt("当前项目目录", Some(&context), None);

        assert_eq!(prompt, "当前项目目录");
    }

    #[test]
    fn compose_envelope_prompt_keeps_current_request_when_context_is_attached() {
        let context = AgentEnvelopeContext {
            include_history: true,
            history_preview: Some("Agent: previous answer".to_owned()),
            runtime_info: Some("rustdesk-dashboard".to_owned()),
            ..Default::default()
        };

        let prompt = compose_envelope_prompt("当前项目目录", Some(&context), None);

        assert_eq!(
            prompt,
            "Conversation history:\nAgent: previous answer\n\nCurrent request:\n当前项目目录"
        );
        assert!(!prompt.contains("Runtime info: rustdesk-dashboard"));
    }

    #[cfg(windows)]
    #[test]
    fn select_windows_codex_command_path_prefers_non_windowsapps_cmd() {
        let where_output = concat!(
            "C:\\Users\\xjf\\AppData\\Roaming\\npm\\codex\n",
            "C:\\Users\\xjf\\AppData\\Roaming\\npm\\codex.cmd\n",
            "C:\\Program Files\\WindowsApps\\OpenAI.Codex\\codex\n",
            "C:\\Program Files\\WindowsApps\\OpenAI.Codex\\codex.exe\n",
        );
        assert_eq!(
            select_windows_codex_command_path(where_output),
            Some("C:\\Users\\xjf\\AppData\\Roaming\\npm\\codex.cmd")
        );
    }

    #[test]
    fn parse_codex_session_index_adds_project_metadata_from_session_meta() {
        let _guard = test_env_lock();
        let fixture = SessionFixture::new("index-project-metadata");
        clear_codex_session_index_cache();
        SESSION_FILE_CACHE.lock().unwrap().clear();

        let project_path = fixture.root.join("ProjectFromMeta");
        fixture.write_session_file(
            "2026/06/session-project.jsonl",
            &json!({
                "type": "session_meta",
                "payload": {
                    "id": "session-project",
                    "cwd": project_path.display().to_string(),
                },
            })
            .to_string(),
        );
        let sessions = parse_codex_session_index(
            r#"{"id":"session-project","updated_at":"2026-06-06T10:00:00Z","thread_name":"Project session"}"#,
        );

        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].project_id, "ProjectFromMeta");
        assert_eq!(
            sessions[0].project_path,
            normalize_session_project_path(&project_path.display().to_string())
        );
    }

    #[test]
    fn parse_codex_session_index_overrides_fallback_project_with_session_meta() {
        let _guard = test_env_lock();
        let fixture = SessionFixture::new("index-project-metadata-override");
        clear_codex_session_index_cache();
        SESSION_FILE_CACHE.lock().unwrap().clear();

        let project_path = fixture.root.join("ProjectFromMeta");
        fixture.write_session_file(
            "2026/06/session-project.jsonl",
            &json!({
                "type": "session_meta",
                "payload": {
                    "id": "session-project",
                    "cwd": project_path.display().to_string(),
                },
            })
            .to_string(),
        );
        let sessions = parse_codex_session_index(
            &json!({
                "id": "session-project",
                "updated_at": "2026-06-06T10:00:00Z",
                "thread_name": "Project session",
                "project_id": "rustdesk",
                "project_path": fixture.root.join("rustdesk").display().to_string(),
            })
            .to_string(),
        );

        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].project_id, "ProjectFromMeta");
        assert_eq!(
            sessions[0].project_path,
            normalize_session_project_path(&project_path.display().to_string())
        );
    }

    #[test]
    fn load_codex_session_index_invalidates_cache_on_file_change() {
        let _guard = test_env_lock();
        let fixture = SessionFixture::new("index-cache");
        clear_codex_session_index_cache();
        SESSION_FILE_CACHE.lock().unwrap().clear();

        fixture.write_index(
            r#"{"id":"session-a","updated_at":"2026-06-05T10:00:00Z","thread_name":"First"}"#,
        );
        let first = load_codex_session_index().unwrap();
        assert_eq!(first.len(), 1);
        assert_eq!(first[0].id, "session-a");

        std::thread::sleep(std::time::Duration::from_millis(20));
        fixture.write_index(
            r#"{"id":"session-b","updated_at":"2026-06-06T10:00:00Z","thread_name":"Second"}"#,
        );
        let second = load_codex_session_index().unwrap();
        assert_eq!(second.len(), 1);
        assert_eq!(second[0].id, "session-b");
    }

    #[test]
    fn resolve_result_session_id_for_new_run_does_not_fall_back_to_existing_latest_session() {
        let _guard = test_env_lock();
        let fixture = SessionFixture::new("resolve-result-session-id");
        clear_codex_session_index_cache();
        SESSION_FILE_CACHE.lock().unwrap().clear();

        fixture.write_index(
            r#"{"id":"session-existing","updated_at":"2026-06-06T10:00:00Z","thread_name":"Existing"}"#,
        );
        let session_index_before = load_codex_session_index().unwrap();
        let project = ProjectConfig {
            id: "rustdesk".to_owned(),
            path: r"C:\work\rustdesk".to_owned(),
            display_name: None,
            tags: Vec::new(),
            executor: None,
            profile: None,
            session: None,
            resume_last: false,
            allow_workspace_write: false,
            thread_mode: Some("new".to_owned()),
            voice_language: None,
            whisper_command: None,
            whisper_model: None,
        };

        let resolved = resolve_result_session_id(&project, &session_index_before);

        assert_eq!(resolved, None);
    }

    #[test]
    fn resolve_target_keeps_explicit_session_when_resume_last_is_true() {
        let _guard = test_env_lock();
        let temp_root =
            std::env::temp_dir().join(format!("rustdesk-agent-bridge-projects-{}", unix_millis()));
        fs::create_dir_all(&temp_root).unwrap();
        let project_path = temp_root.join("rustdesk");
        fs::create_dir_all(&project_path).unwrap();
        let _projects_guard = ConfigOptionGuard::replace(
            PROJECTS,
            json!([
                {
                    "id": "rustdesk",
                    "path": project_path.display().to_string(),
                    "resume_last": false
                }
            ])
            .to_string(),
        );

        let resolved = resolve_target(&AgentRunRequest {
            request_id: "req-continue".to_owned(),
            project: "rustdesk".to_owned(),
            prompt: "reply with exactly CONT_OK".to_owned(),
            mode: Some("read-only".to_owned()),
            require_confirmation: Some(true),
            executor: None,
            profile: None,
            session: Some("019ea229-79f1-7d81-bd1e-83b03aef4e92".to_owned()),
            resume_last: Some(true),
        })
        .unwrap();

        assert_eq!(
            resolved.session.as_deref(),
            Some("019ea229-79f1-7d81-bd1e-83b03aef4e92")
        );
        assert!(!resolved.resume_last);

        let _ = fs::remove_dir_all(&temp_root);
    }

    #[test]
    fn resolve_target_uses_bound_session_project_when_project_is_not_configured() {
        let _guard = test_env_lock();
        let fixture = SessionFixture::new("resolve-session-project-fallback");
        clear_codex_session_index_cache();
        SESSION_FILE_CACHE.lock().unwrap().clear();

        let rustdesk_path = fixture.root.join("rustdesk");
        fs::create_dir_all(&rustdesk_path).unwrap();
        let blueprint_path = fixture.root.join("BlueprintHarness");
        fs::create_dir_all(&blueprint_path).unwrap();
        let _projects_guard = ConfigOptionGuard::replace(
            PROJECTS,
            json!([
                {
                    "id": "rustdesk",
                    "path": rustdesk_path.display().to_string(),
                    "resume_last": false
                }
            ])
            .to_string(),
        );
        fixture.write_session_file(
            "2026/06/rollout-2026-06-07T20-16-38-session-blueprint-fallback.jsonl",
            &json!({
                "type": "session_meta",
                "payload": {
                    "id": "session-blueprint-fallback",
                    "cwd": blueprint_path.display().to_string(),
                },
            })
            .to_string(),
        );

        let resolved = resolve_target(&AgentRunRequest {
            request_id: "req-session-project".to_owned(),
            project: "BlueprintHarness".to_owned(),
            prompt: "reply with exactly CONT_OK".to_owned(),
            mode: Some("read-only".to_owned()),
            require_confirmation: Some(true),
            executor: None,
            profile: None,
            session: Some("session-blueprint-fallback".to_owned()),
            resume_last: Some(true),
        })
        .unwrap();

        assert_eq!(resolved.id, "BlueprintHarness");
        assert_eq!(
            resolved.path,
            normalize_session_project_path(&blueprint_path.display().to_string())
        );
        assert_eq!(
            resolved.session.as_deref(),
            Some("session-blueprint-fallback")
        );
        assert!(!resolved.resume_last);
        assert!(!resolved.allow_workspace_write);
    }

    #[test]
    fn extract_codex_thread_id_reads_thread_started_event() {
        let stdout = concat!(
            "{\"type\":\"thread.started\",\"thread_id\":\"019ea203-7c18-7750-9282-3e7ca79f50ad\"}\n",
            "{\"type\":\"response_item\",\"payload\":{\"role\":\"assistant\",\"text\":\"done\"}}\n"
        );
        assert_eq!(
            extract_codex_thread_id(stdout),
            Some("019ea203-7c18-7750-9282-3e7ca79f50ad".to_owned())
        );
    }

    #[test]
    fn find_session_file_cached_recovers_when_cached_path_disappears() {
        let _guard = test_env_lock();
        let fixture = SessionFixture::new("session-file-cache");
        clear_codex_session_index_cache();
        SESSION_FILE_CACHE.lock().unwrap().clear();

        let first_path =
            fixture.write_session_file("2026/06/session-1.jsonl", "{\"type\":\"response_item\"}");
        let resolved = find_session_file_cached("session-1").unwrap();
        assert_eq!(resolved, first_path);

        fs::remove_file(&first_path).unwrap();
        let second_path =
            fixture.write_session_file("2026/07/session-1.jsonl", "{\"type\":\"response_item\"}");
        let recovered = find_session_file_cached("session-1").unwrap();
        assert_eq!(recovered, second_path);
    }

    #[test]
    fn load_session_line_index_ignores_blank_lines() {
        let _guard = test_env_lock();
        let fixture = SessionFixture::new("line-index");
        SESSION_LINE_INDEX_CACHE.lock().unwrap().clear();

        let path = fixture.write_session_file(
            "2026/08/session-line.jsonl",
            "\n{\"type\":\"response_item\",\"payload\":{\"role\":\"user\",\"text\":\"one\"}}\r\n\r\n{\"type\":\"response_item\",\"payload\":{\"role\":\"assistant\",\"text\":\"two\"}}\n",
        );
        let index = load_session_line_index(&path).unwrap();
        assert_eq!(index.lines.len(), 2);

        let lines = read_session_lines(&path, &index.lines).unwrap();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains("\"one\""));
        assert!(lines[1].contains("\"two\""));
    }

    #[test]
    fn load_codex_session_detail_reads_requested_page_without_full_text_split() {
        let _guard = test_env_lock();
        let fixture = SessionFixture::new("session-detail-page");
        clear_codex_session_index_cache();
        SESSION_FILE_CACHE.lock().unwrap().clear();
        SESSION_LINE_INDEX_CACHE.lock().unwrap().clear();

        fixture.write_index(
            r#"{"id":"session-page","updated_at":"2026-06-06T10:00:00Z","thread_name":"Paged"}"#,
        );
        fixture.write_session_file(
            "2026/09/session-page.jsonl",
            concat!(
                "{\"type\":\"response_item\",\"timestamp\":\"1\",\"payload\":{\"role\":\"user\",\"text\":\"first\"}}\n",
                "{\"type\":\"response_item\",\"timestamp\":\"2\",\"payload\":{\"role\":\"assistant\",\"text\":\"second\"}}\n",
                "{\"type\":\"response_item\",\"timestamp\":\"3\",\"payload\":{\"role\":\"assistant\",\"text\":\"third\"}}\n"
            ),
        );

        let detail = load_codex_session_detail("session-page", Some(2), 1).unwrap();
        assert_eq!(detail.messages.len(), 1);
        assert_eq!(detail.messages[0].text, "second");
        assert_eq!(detail.next_cursor, Some(1));
    }

    #[test]
    fn load_codex_session_detail_reads_file_even_when_session_index_is_missing() {
        let _guard = test_env_lock();
        let fixture = SessionFixture::new("session-detail-without-index");
        clear_codex_session_index_cache();
        SESSION_FILE_CACHE.lock().unwrap().clear();
        SESSION_LINE_INDEX_CACHE.lock().unwrap().clear();

        fixture.write_session_file(
            "2026/10/rollout-2026-06-07T20-16-38-session-orphan.jsonl",
            concat!(
                "{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"E:\\\\rustDesk\"}}\n",
                "{\"type\":\"response_item\",\"timestamp\":\"1\",\"payload\":{\"role\":\"assistant\",\"text\":\"orphan reply\"}}\n"
            ),
        );

        let detail = load_codex_session_detail("session-orphan", None, 50).unwrap();
        assert_eq!(detail.id, "session-orphan");
        assert_eq!(detail.title, "session-orphan");
        assert_eq!(detail.project_id, "rustdesk");
        assert_eq!(detail.messages.len(), 1);
        assert_eq!(detail.messages[0].text, "orphan reply");
    }

    #[test]
    fn public_session_detail_redacts_paths_tokens_and_raw_events() {
        let detail = CodexSessionDetail {
            id: "session-private".to_owned(),
            title: "Private".to_owned(),
            updated_at: "2026-06-08T00:00:00Z".to_owned(),
            project_id: "rustdesk".to_owned(),
            project_path: r"C:\work\rustdesk".to_owned(),
            messages: vec![CodexSessionMessage {
                role: "assistant".to_owned(),
                text: "Token: private-token\nOutput at C:\\work\\rustdesk".to_owned(),
                timestamp: "1".to_owned(),
            }],
            timeline: vec![AgentTimelineEvent {
                stage: "event".to_owned(),
                summary: "cwd C:\\work\\rustdesk".to_owned(),
                ts: 1,
                raw: Some(json!({"cwd": "C:\\work\\rustdesk"})),
            }],
            raw_events: vec![json!({"token": "private-token"})],
            next_cursor: None,
        };

        let public = public_session_detail(detail);

        assert_eq!(public.project_path, "<PROJECT_PATH>/rustdesk");
        assert!(public.raw_events.is_empty());
        assert_eq!(public.timeline[0].raw, None);
        assert!(!public.messages[0].text.contains("private-token"));
        assert!(!public.messages[0].text.contains(r"C:\work\rustdesk"));
        assert!(!public.timeline[0].summary.contains(r"C:\work\rustdesk"));
    }

    #[test]
    fn task_snapshot_detail_uses_public_task_view() {
        let task = AgentTaskInfo {
            request_id: "req-private".to_owned(),
            project: "rustdesk".to_owned(),
            status: "needs_confirmation".to_owned(),
            text: "Token: private-token\nPlan for C:\\work\\rustdesk".to_owned(),
            sandbox: "read-only".to_owned(),
            started_at: 1,
            updated_at: 2,
            exit_code: None,
            error: "secret at C:\\work\\rustdesk".to_owned(),
            token: Some("private-token".to_owned()),
            cancel_requested: false,
            detail_json:
                r#"{"kind":"codexResult","outputFile":"C:\\work\\out.json","token":"private-token"}"#
                    .to_owned(),
            timeline: vec![AgentTimelineEvent {
                stage: "needs_confirmation".to_owned(),
                summary: "Token: private-token".to_owned(),
                ts: 1,
                raw: Some(json!({"token": "private-token"})),
            }],
            raw_events: vec![json!({"token": "private-token"})],
        };

        let snapshot = task_snapshot_detail(&task);
        let item = snapshot.get("item").unwrap();

        assert!(item.get("token").is_none());
        assert!(item.get("raw_events").is_none());
        assert!(!snapshot.to_string().contains("private-token"));
        assert!(!snapshot.to_string().contains(r"C:\work"));
        assert!(snapshot.to_string().contains("<redacted>"));
    }

    #[test]
    fn upsert_task_updates_existing_task_in_place() {
        let _guard = test_env_lock();
        TASKS.lock().unwrap().clear();

        upsert_task(
            "req-1",
            "rustdesk",
            "running",
            "first",
            "read-only",
            None,
            "",
            None,
            Some("{\"kind\":\"seed\"}".to_owned()),
            Some(json!({"seq": 1})),
        );
        let started_at = TASKS.lock().unwrap().get("req-1").unwrap().started_at;
        TASKS
            .lock()
            .unwrap()
            .get_mut("req-1")
            .unwrap()
            .cancel_requested = true;

        upsert_task(
            "req-1",
            "rustdesk",
            "done",
            "second",
            "read-only",
            Some(0),
            "",
            None,
            None,
            Some(json!({"seq": 2})),
        );

        let task = TASKS.lock().unwrap().get("req-1").cloned().unwrap();
        assert_eq!(task.started_at, started_at);
        assert!(task.cancel_requested);
        assert_eq!(task.status, "done");
        assert_eq!(task.detail_json, "{\"kind\":\"seed\"}");
        assert_eq!(task.timeline.len(), 2);
        assert_eq!(task.raw_events.len(), 2);
    }

    #[test]
    fn upsert_task_bounds_timeline_and_raw_events_without_resetting_task() {
        let _guard = test_env_lock();
        TASKS.lock().unwrap().clear();

        for idx in 0..(MAX_TASK_TIMELINE + 4) {
            upsert_task(
                "req-bounds",
                "rustdesk",
                "running",
                &format!("tick-{idx}"),
                "read-only",
                None,
                "",
                None,
                None,
                Some(json!({"idx": idx})),
            );
        }

        let task = TASKS.lock().unwrap().get("req-bounds").cloned().unwrap();
        assert_eq!(task.timeline.len(), MAX_TASK_TIMELINE);
        assert_eq!(task.raw_events.len(), MAX_TASK_RAW_EVENTS);
        assert_eq!(
            task.timeline.first().map(|item| item.summary.as_str()),
            Some("tick-4")
        );
        let expected_last = format!("tick-{}", MAX_TASK_TIMELINE + 3);
        assert_eq!(
            task.timeline.last().map(|item| item.summary.as_str()),
            Some(expected_last.as_str())
        );
        assert_eq!(
            task.raw_events
                .first()
                .and_then(|value| value.get("idx"))
                .and_then(Value::as_u64),
            Some((MAX_TASK_TIMELINE + 4 - MAX_TASK_RAW_EVENTS) as u64)
        );
        assert_eq!(
            task.raw_events
                .last()
                .and_then(|value| value.get("idx"))
                .and_then(Value::as_u64),
            Some((MAX_TASK_TIMELINE + 3) as u64)
        );
    }

    #[test]
    fn materialize_voice_audio_cleans_stale_bridge_temp_files() {
        let _guard = test_env_lock();
        let _fixture = SessionFixture::new("voice-cleanup");

        let data_dir = bridge_data_dir();
        fs::create_dir_all(&data_dir).unwrap();
        let stale = data_dir.join("voice-stale.wav");
        let current = data_dir.join("voice-current.wav");
        let other = data_dir.join("note.txt");
        fs::write(&stale, b"stale").unwrap();
        fs::write(&current, b"current").unwrap();
        fs::write(&other, b"other").unwrap();
        cleanup_stale_voice_temp_files_with_max_age(&current, std::time::Duration::ZERO);
        assert!(!stale.exists());
        assert!(current.exists());
        assert!(other.exists());
    }

    #[test]
    fn materialize_voice_audio_keeps_explicit_audio_path_untouched() {
        let _guard = test_env_lock();
        let fixture = SessionFixture::new("voice-explicit-path");

        let explicit = fixture.root.join("explicit.wav");
        fs::write(&explicit, b"explicit").unwrap();

        let data_dir = bridge_data_dir();
        fs::create_dir_all(&data_dir).unwrap();
        let stale = data_dir.join("voice-stale.wav");
        let current = data_dir.join("voice-current.wav");
        fs::write(&stale, b"stale").unwrap();
        fs::write(&current, b"current").unwrap();

        let req = VoiceEnvelope {
            audio_path: Some(explicit.display().to_string()),
            audio_base64: None,
            language: None,
            normalized_prompt: None,
        };
        let resolved = materialize_voice_audio(&req).unwrap();

        assert_eq!(resolved, explicit);
        assert!(stale.exists());
        assert!(current.exists());
    }

    #[test]
    fn materialize_voice_audio_base64_writes_current_voice_file() {
        let _guard = test_env_lock();
        let _fixture = SessionFixture::new("voice-base64-write");

        let req = VoiceEnvelope {
            audio_path: None,
            audio_base64: Some("dGVzdA==".to_owned()),
            language: None,
            normalized_prompt: None,
        };
        let generated = materialize_voice_audio(&req).unwrap();

        assert!(generated.is_file());
        assert_eq!(
            generated.extension().and_then(|value| value.to_str()),
            Some("wav")
        );
        assert_eq!(fs::read(&generated).unwrap(), b"test");
    }

    #[test]
    fn discover_codex_skill_entries_reads_local_and_system_skills() {
        let _guard = test_env_lock();
        let fixture = SessionFixture::new("discover-skills");

        fixture.write_skill(
            "skills/ui-ux-pro-max/SKILL.md",
            "---\nname: ui-ux-pro-max\ndescription: UI/UX design intelligence\n---\n# ui-ux-pro-max\n",
        );
        fixture.write_skill(
            "skills/.system/openai-docs/SKILL.md",
            "---\nname: \"openai-docs\"\ndescription: \"Official OpenAI docs workflow\"\n---\n# OpenAI Docs\n",
        );
        fixture.write_skill("skills/assets/README.md", "not a skill");

        let discovered = discover_codex_skill_entries();

        assert_eq!(discovered.len(), 2);
        let local = discovered
            .iter()
            .find(|entry| entry.id == "ui-ux-pro-max")
            .unwrap();
        assert_eq!(local.group, "local");
        assert_eq!(local.title, "ui-ux-pro-max");
        assert_eq!(local.description, "UI/UX design intelligence");

        let system = discovered
            .iter()
            .find(|entry| entry.id == "openai-docs")
            .unwrap();
        assert_eq!(system.group, "system");
        assert_eq!(system.title, "openai-docs");
        assert_eq!(system.description, "Official OpenAI docs workflow");
    }

    #[test]
    fn merge_discovered_codex_skills_keeps_catalog_entry_without_duplicates() {
        let _guard = test_env_lock();
        let fixture = SessionFixture::new("merge-discovered-skills");

        fixture.write_skill(
            "skills/ui-ux-pro-max/SKILL.md",
            "---\nname: ui-ux-pro-max\ndescription: discovered description\n---\n# ui-ux-pro-max\n",
        );
        fixture.write_skill(
            "skills/.system/openai-docs/SKILL.md",
            "---\nname: openai-docs\ndescription: system description\n---\n# OpenAI Docs\n",
        );

        let merged = merge_discovered_codex_skills(vec![SkillCatalogEntry {
            id: "ui-ux-pro-max".to_owned(),
            title: "Catalog Title".to_owned(),
            group: "custom".to_owned(),
            description: "Catalog description".to_owned(),
            enabled: true,
            mirror_name: "ui-ux-pro-max".to_owned(),
            tags: vec!["curated".to_owned()],
            updated_at: 7,
        }]);

        assert_eq!(merged.len(), 2);
        let catalog = merged
            .iter()
            .find(|entry| entry.id == "ui-ux-pro-max")
            .unwrap();
        assert_eq!(catalog.title, "Catalog Title");
        assert_eq!(catalog.description, "Catalog description");
        assert_eq!(catalog.group, "custom");

        let system = merged
            .iter()
            .find(|entry| entry.id == "openai-docs")
            .unwrap();
        assert_eq!(system.group, "system");
        assert_eq!(system.description, "system description");
    }

    struct SessionFixture {
        root: PathBuf,
        previous_codex_home: Option<std::ffi::OsString>,
    }

    impl SessionFixture {
        fn new(name: &str) -> Self {
            let root = std::env::temp_dir().join(format!(
                "rustdesk-agent-bridge-test-{}-{}",
                name,
                unix_millis()
            ));
            if root.exists() {
                let _ = fs::remove_dir_all(&root);
            }
            fs::create_dir_all(root.join("sessions")).unwrap();
            let previous_codex_home = std::env::var_os("CODEX_HOME");
            std::env::set_var("CODEX_HOME", &root);
            Self {
                root,
                previous_codex_home,
            }
        }

        fn write_index(&self, content: &str) {
            fs::write(self.root.join("session_index.jsonl"), content).unwrap();
        }

        fn write_session_file(&self, relative: &str, content: &str) -> PathBuf {
            let path = self.root.join("sessions").join(relative);
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent).unwrap();
            }
            fs::write(&path, content).unwrap();
            path
        }

        fn write_skill(&self, relative: &str, content: &str) -> PathBuf {
            let path = self.root.join(relative);
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent).unwrap();
            }
            fs::write(&path, content).unwrap();
            path
        }
    }

    impl Drop for SessionFixture {
        fn drop(&mut self) {
            clear_codex_session_index_cache();
            SESSION_FILE_CACHE.lock().unwrap().clear();
            SESSION_LINE_INDEX_CACHE.lock().unwrap().clear();
            TASKS.lock().unwrap().clear();
            if let Some(previous) = self.previous_codex_home.take() {
                std::env::set_var("CODEX_HOME", previous);
            } else {
                std::env::remove_var("CODEX_HOME");
            }
            let _ = fs::remove_dir_all(&self.root);
        }
    }
}
