// Generate a standalone guide from actual Flutter fixture screenshots.
// DVT_GUIDE_OUTPUT=build/dvt-guide flutter test test/ui/dvt_guide_screens_test.dart
// node tool/build_dvt_guide.mjs
import {readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';

const source = path.resolve(process.env.DVT_GUIDE_OUTPUT || 'build/dvt-guide');
const target = path.resolve('docs/DVT-App-功能使用说明-v0.0.2.html');
const chapters = [
  ['connect', '查找与连接设备', [['welcome','首次打开'],['discovery','选择目标设备'],['device-unauthenticated','等待安全码认证']], [
    ['连接设备 → 开始查找','显示附近有名称的 BLE 设备；相同设备不重复列出。扫描暂不按广播厂商或名称前缀严格过滤，无名称设备不显示。'],
    ['允许蓝牙权限','Android 12+ 请求附近设备权限；Android 6–11 还需定位权限及系统定位服务。iOS 请求蓝牙权限。拒绝时显示说明，可到系统设置开启后重试。'],
    ['系统蓝牙关闭','Android 在支持时调起系统开启确认；iOS 显示平台说明并引导设置，不承诺 App 可直接开启蓝牙或直达系统蓝牙页。'],
    ['选择设备 → 连接','进入连接、服务发现、订阅准备过程。必需特征或属性不匹配时明确失败；连接成功后出现“认证设备 / 首次绑定设备”。扫描看到设备不等于协议兼容。'],
    ['重新连接 / 自动回连','已成功连接的设备会保留连接标识；连接意外中断后按当前回连策略扫描并尝试恢复，失败仍可手动重试。iOS 使用系统外设标识，不提供真实 MAC。重连后重新认证。'],
  ]],
  ['auth','认证与首次绑定', [['security-example','输入安全码'],['binding-wait','等待设备按键'],['device-idle','认证完成']], [
    ['已绑定设备 → 认证设备','输入当前设备正确的 6 字节安全码。可用 6 位可打印文本，或 12 位十六进制表示；两种输入按各自编码转换，示例不是通用密码。'],
    ['显示 / 隐藏 → 开始认证','显示状态切换不改变输入；格式不完整时无法提交。设备回复成功后加载信息、订阅业务通道，录音与文件入口可用。'],
    ['首次绑定设备','输入安全码提交后，在 60 秒内短按设备键确认。绑定成功后 App 自动继续当前连接认证；不是仅看到“绑定成功”就开放业务。'],
    ['取消 / 认证错误 / 超时','取消输入不发送认证；错误或超时显示失败，不伪装认证成功。核对码和绑定状态后重试，连接已断开则先重连。'],
  ]],
  ['record','设备录音控制', [['device-idle','待机'],['device-recording','正在录音'],['device-paused','暂停录音']], [
    ['允许设备录音','已认证且配置就绪时可切换；设备确认后更新开关。未同意或处于隐私模式时禁止开始 / 继续录音。'],
    ['开始录音','收到设备确认后显示录音状态，“开始录音”变为“暂停录音”，同时提供“结束录音”。操作中暂时禁止重复下发。'],
    ['暂停录音 → 继续录音','状态依次显示暂停、录音中；暂停时主按钮变为“继续录音”。'],
    ['结束录音','设备回到待机，等待封装完成后可在设备文件中刷新查看新录音；本页不进行手机麦克风录音。'],
    ['设备已动作但 App 未更新','先点“刷新状态”读取设备真实录音状态，再决定下一步；不重复发送开始命令来猜测状态。异常状态不会显示成待机。'],
  ]],
  ['status','设备状态与隐私设置', [['device-settings','设备状态'],['privacy-menu','默认隐私时长']], [
    ['刷新状态','读取设备信息、录音状态、隐私与同步状态、电量和存储空间；页面显示最新可用结果。文件数量是上次查询值，不是实时统计。'],
    ['默认隐私时长','选择手动退出、10 / 30 / 60 分钟，设备确认后更新配置。这个入口设置默认时长，不是进入或退出隐私模式的按钮。'],
    ['查看电量 / 存储 / 版本','展示设备回报的电量、充电状态、空间及版本。未知或读取失败保持明确提示，不显示编造数值。'],
    ['设备侧进入隐私模式','App 接收状态变化；开始 / 继续录音受限制。退出后刷新确认状态，再继续测试。'],
  ]],
  ['files','设备文件与下载', [['dvt-files','设备文件'],['download-progress','下载进度'],['download-saved','保存完成']], [
    ['设备录音文件 → 刷新','逐页读取设备文件列表，展示文件名和大小，直到设备返回空页；重复文件键或列表异常报错。'],
    ['保存到 App','先检查元数据，再下载并校验文件长度和 CRC32；仅当前文件显示保存进度，其他操作暂时禁用。'],
    ['保存成功 → 播放','显示“已保存到手机”和“播放”；点击进入本地播放器。仅下载不会删除设备上的源文件。'],
    ['下载断连 / 中途退出','保留有效断点。重连并认证后重新保存同一文件，校验元数据一致才续传；文件变化不能拼接旧内容。'],
    ['手机副本被删除后返回','重新检查本地文件，失效标记恢复成“保存到 App”，可再次下载。'],
  ]],
  ['metadata','文件元数据', [['file-metadata','元数据查看']], [
    ['文件右下方 → 元数据','显示原文件名、大小、CRC32、文件状态、UTC 起始时间、录音会话、分段序号、时钟质量、UTC 修正及原始文件键字节。'],
    ['核对同一录音','文件名、大小与设备列表对应；同一录音会话的分段可按会话号及分段序号核对。V1.6 元数据没有录音时长字段。'],
    ['关闭','关闭弹窗回到文件列表；不会修改文件，也不会发送删除或归档确认。'],
  ]],
  ['archive','云端归档与设备空间释放', [['archive-confirmation','归档确认'],['archive-complete','归档完成'],['archive-recovery','待确认恢复']], [
    ['归档并释放 → 归档','先保存并校验手机文件，再获得云端可靠保存回执，最后向设备确认归档；只有设备返回可回收或已删除才显示成功。手机录音仍保留。'],
    ['取消归档','关闭确认窗，不上传也不下发释放请求。'],
    ['未配置归档服务 / 上传失败','明确显示失败，不能释放设备源文件。需构建配置 DVT_ARCHIVE_URL，服务满足 App 要求的可靠保存回执；这个 HTTPS 服务不是固件接口。'],
    ['云端完成但设备确认丢失','保留待确认记录。重连并认证后在待确认区域继续；即使源文件已不在设备列表，仍可按原文件信息恢复确认。'],
    ['设备回复忙 / 校验不一致 / 非终态','归档不显示成功，保留恢复信息。设备状态为可回收时可能稍后才释放空间，不能把空间暂未变化当作归档失败。'],
  ]],
  ['library','已保存录音与播放', [['library','本地录音'],['player-playing','播放与拖动'],['library-menu','录音管理']], [
    ['首页 / 详情 / 文件页 → 已保存录音','打开手机上保存的设备录音；不要求设备保持连接。点击录音进入播放页。'],
    ['播放 / 暂停 / 进度拖动','显示播放位置与时长，拖动后从对应位置播放。未知总时长时显示未知并禁用拖动，不假装 0 秒。'],
    ['上一条 / 下一条','在当前录音集合中切换；没有相邻录音时对应操作不可用。单条文件入口可能没有相邻录音。'],
    ['更多操作 → 重命名','输入新名称保存后列表更新；只改手机记录名称，不改设备文件键。'],
    ['更多操作 → 删除','二次确认后删除手机副本；不删除硬件源文件。设备源文件存在时可重新下载。'],
    ['iOS 播放 OGG / Opus','当前构建不支持该格式时显示不可播放；文件下载和完整性校验仍可执行。不能把下载成功当作 iOS 播放能力验证。'],
  ]],
  ['audio','DVT 实时音频验证', [['dvt-entry','专项入口'],['audio-streaming','正在接收'],['audio-stopped','停止后保留统计'],['audio-capacity','传输容量不足']], [
    ['DVT 实时音频验证 → 开始验证','设备提供 FA18，当前已认证且实际 ATT MTU 至少 489 时可启动。先准备接收，再启用音频流，页面进入正在接收。'],
    ['观察帧数 / 字节 / 时长 / 吞吐','随实际有效音频回包增加；仅统计接收到的内容，不进行实时播放。协议没有序号，因此不显示推测的丢包率。'],
    ['停止验证 / 返回','关闭音频流，停止本次验证自行启动的录音并释放监听；统计保留供核对。关闭失败时保留停止入口或清理连接，不假装设备已停止。'],
    ['iOS 或其他手机 MTU 不足','显示明确容量限制，阻止启动；不能通过 UI 或强行写入解决固件固定帧长度与系统能力不匹配。缺少 FA18 时入口不可用。'],
  ]],
  ['ota','DVT 固件升级', [['ota-idle','输入升级清单'],['ota-ready','升级包已校验'],['ota-transferring','传输进度'],['ota-reconnect','等待重连核验'],['ota-complete','版本核验成功']], [
    ['读取并校验升级包','填写固件团队提供的 HTTPS 清单地址。目标型号、版本、镜像完整性及抓包确认参数有效后展示包信息；示例地址不可用于真实升级。'],
    ['开始 / 恢复升级','当前连接已认证、OTA 特征就绪、没有冲突传输时启动；显示准备、发送字节进度及整镜像校验状态。接收监听先于发送。'],
    ['传输中断 / 超时','停止继续发送并显示错误。保留适用的检查点；重新连接认证、读取同一清单后恢复，由设备实际偏移决定能否续传。'],
    ['取消升级 / 返回','停止任务并释放传输连接；即使初始化此时才完成，也不会在退出后继续启动升级。取消不代表设备版本已回退。'],
    ['设备完成校验并重启','显示等待重连。回设备页重新连接并认证，再进入升级页读取同一清单，点击“重连后核验版本”。'],
    ['重连后核验版本','只有设备实际版本与目标一致，才显示升级完成；发送到 100% 不等于升级完成。需要固件提供真实 WQOTA 帧头并确认最终校验语义。'],
  ]],
  ['logs','实时日志与本地保存', [['logs','实时日志'],['logs-paused','暂停跟随'],['logs-exported','导出路径']], [
    ['详情右上角 → 实时日志','看到扫描、连接、GATT、订阅、发送、接收、解析、等待、成功或超时的日志。Debug 记录原始数据包与中文步骤提示，按同一设备和时间定位。'],
    ['暂停跟随 / 继续跟随','暂停自动滚动方便查看；不停止底层日志采集。继续后跟随新日志。'],
    ['清空视图','只清除当前页面已展示的日志，不删除已落盘日志；暂停跟随时也立即更新视图。'],
    ['导出日志','刷入本地文件并提示实际保存地址。Android 公共目录 Download/AIPIN/logs，iOS 文件 App 中本 App 的 Documents/AIPIN/logs；以页面输出路径为准。'],
    ['公共目录未见文件','Debug 才启用日志持久化。查看导出结果与权限，旧 Android 可能需要存储权限；公共镜像失败不代表内部日志不存在。'],
  ]],
  ['check','设备检查与记录', [['observation','验证场景'],['manual-observation','人工观察'],['records','检查记录']], [
    ['设备检查 → 选择场景','使用当前状态快照与本次会话事件判断通过、失败或不可验证，同时显示原因或缺失证据。不是自动替硬件跑完所有测试。'],
    ['VAD 录音 / 电池充电 / 恢复','按场景准备真实设备事件；缺少录音开始、静音结束、充电字段或恢复前后状态时，不应显示通过。'],
    ['物理反馈 → 记录人工观察','填写实际按键、LED、振动等观察并保存；空备注不能证明验证通过。'],
    ['保存验证结果 → 检查记录','保存到本地后可查看；保存失败明确提示且可重试。“保存成功”只代表记录已写入，不代表场景通过。'],
    ['待机功耗','只有提供了所需测量证据才可验证；常规 BLE 状态字段不能代替真实功耗测试。'],
  ]],
  ['manage','断开与解绑', [['device-management','设备管理'],['disconnect-confirmation','断开确认'],['unbind-confirmation','解绑确认']], [
    ['断开设备','确认后断开当前 BLE 连接并回收任务；仅断开不清除硬件录音、绑定与手机副本。'],
    ['设备管理 → 解绑设备','先确认风险，再检查设备空闲、无冲突传输、全部文件已归档或列表为空；满足条件后输入安全码。'],
    ['确认解绑','持久化解绑意图后发送，设备成功回复才确认完成。解绑会清除硬件用户数据；手机已保存的录音不在此操作中删除。'],
    ['解绑中断 → 恢复解绑','重新连接后使用同一安全码继续原解绑，不是撤销解绑；普通认证入口不会绕过待恢复状态。'],
  ]],
  ['settings','设置与异常预期', [['settings','设置']], [
    ['跟随系统 / 浅色 / 深色','切换并保存主题偏好；界面沿用 EVT 的统一卡片、文字操作和确认交互。'],
    ['附近设备 → 系统设置 → 返回','返回 App 后重新读取权限状态，再开始扫描或连接。'],
    ['设备断电 / 蓝牙关闭 / App 重启','当前会话权限失效，未完成动作不能显示成功；恢复连接后重新认证并刷新状态。适用的下载、归档、OTA 检查点可供恢复。'],
    ['App 退后台或锁屏','连接与任务受 Android / iOS 系统调度限制；不承诺无限后台连接。回前台按实际连接状态恢复，不能使用旧连接权限继续写入。'],
    ['错误、缺特征或无回包','界面给出失败或重试路径；日志应能区分未发送、原生写入完成、收到回包、业务解析成功和等待超时。'],
  ]],
];
const escape = value => String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const sections = [];
let count = 0;
for (let index=0; index<chapters.length; index++) {
  const [id,title,shots,rows] = chapters[index];
  const figures = [];
  for (const [name,label] of shots) {
    const bytes = await readFile(path.join(source, name+'.png'));
    figures.push('<figure><button class="screen" aria-label="放大：'+escape(label)+'"><img width="360" height="800" loading="lazy" alt="'+escape(label)+' · 预期界面，示例数据" src="data:image/png;base64,'+bytes.toString('base64')+'"></button><figcaption><b>'+escape(label)+'</b><small>预期界面 · 示例数据 · 点击放大</small></figcaption></figure>');
    count++;
  }
  sections.push('<section id="'+id+'" class="chapter"><div class="chapter-header"><span class="number">'+String(index+1).padStart(2,'0')+'</span><h2>'+title+'</h2></div><div class="screens">'+figures.join('')+'</div><div class="table-wrap"><table><thead><tr><th>操作 / 场景</th><th>预期结果</th></tr></thead><tbody>'+rows.map(([a,b])=>'<tr><td>'+escape(a)+'</td><td>'+escape(b)+'</td></tr>').join('')+'</tbody></table></div></section>');
}
const css = `
:root{--ink:#162b39;--muted:#526777;--bg:#f4f6f4;--line:#dce4e1;--green:#14584d;--soft:#e8f2ed}*{box-sizing:border-box}html{scroll-padding-top:24px}body{margin:0;background:var(--bg);color:var(--ink);font-family:"Microsoft YaHei","PingFang SC",system-ui,sans-serif;line-height:1.75}a{color:inherit}button{font:inherit;cursor:pointer}button:focus-visible,a:focus-visible{outline:3px solid #bf751d;outline-offset:4px}.layout{max-width:1540px;margin:auto;display:grid;grid-template-columns:220px minmax(0,1fr);gap:36px;padding:28px 40px}aside{position:sticky;top:24px;height:calc(100vh - 48px);overflow:auto}.wordmark{font-size:25px;font-weight:800;letter-spacing:4px;color:var(--green)}.edition{color:var(--muted);font-size:12px;margin:6px 0 24px}nav a{display:block;text-decoration:none;font-size:13px;padding:9px 10px;border-left:2px solid transparent;border-radius:0 8px 8px 0}nav a:hover,nav a.active{background:var(--soft);border-color:var(--green);color:var(--green)}nav span{font-size:11px;color:#84988d;margin-right:10px}.print{border:1px solid var(--line);background:white;border-radius:8px;padding:8px 14px;margin-top:20px}main{min-width:0}.hero{background:var(--ink);color:white;border-radius:20px;padding:38px}.kicker{font-size:11px;letter-spacing:3px;color:#bbd5c8}.hero h1{font-size:clamp(28px,3.5vw,46px);line-height:1.3;margin:16px 0}.hero p{color:#d3e0e5;font-size:14px}.badges{display:flex;flex-wrap:wrap;gap:8px}.badges span{font-size:11px;border:1px solid #54706f;border-radius:24px;padding:4px 12px}.intro{background:#edf5ef;color:#315a4f;border:1px solid #cbdcd2;padding:16px 20px;border-radius:12px;font-size:13px;margin:20px 0}.quick{display:flex;flex-wrap:wrap;gap:8px;margin:20px 0}.quick a{text-decoration:none;background:white;border:1px solid var(--line);padding:10px 15px;border-radius:9px;font-size:13px}.chapter{background:white;padding:28px;margin:28px 0;border:1px solid var(--line);border-radius:16px;scroll-margin-top:24px;box-shadow:0 12px 34px #16352b0b}.chapter-header{display:flex;gap:16px;align-items:center;margin-bottom:24px}.number{font-size:13px;color:var(--green);background:var(--soft);border-radius:12px;padding:9px 12px;font-weight:bold}h2{font-size:23px;line-height:1.4;margin:0}.screens{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:20px;align-items:start;margin-bottom:26px}figure{margin:0;text-align:center}.screen{display:block;width:100%;max-width:240px;margin:auto;padding:5px;border:1px solid #d9ded9;border-radius:18px;background:#f8f6f3;box-shadow:0 8px 20px #162b3912}.screen img{width:100%;height:auto;display:block;border-radius:13px}figcaption{padding-top:12px;font-size:13px}figcaption small{display:block;font-size:10px;color:var(--muted);margin-top:4px}.table-wrap{overflow-x:auto}table{width:100%;border-collapse:collapse;table-layout:fixed;font-size:13px}th,td{text-align:left;vertical-align:top;padding:13px 14px;border-bottom:1px solid var(--line);overflow-wrap:anywhere}th{background:#f0f5f1;color:var(--green);font-weight:600}th:first-child{width:27%}td:first-child{font-weight:600}footer{text-align:center;font-size:12px;color:var(--muted);padding:25px}dialog{border:0;border-radius:16px;max-width:94vw;max-height:94vh;padding:14px;background:#f8f6f3}dialog::backdrop{background:#071410cc}dialog img{display:block;max-width:82vw;max-height:78vh;width:auto;height:auto;margin:auto}dialog p{font-size:12px;text-align:center}.close{display:block;margin:0 0 10px auto;border:1px solid var(--line);border-radius:7px;padding:5px 13px;background:white}@media(max-width:1000px){.layout{grid-template-columns:175px minmax(0,1fr);padding:20px;gap:20px}.chapter{padding:20px}.screens{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:680px){.layout{display:block;padding:12px}aside{position:static;height:auto;margin-bottom:20px}nav{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:2px}.edition{margin-bottom:12px}.hero{padding:26px 22px}.chapter{padding:18px 12px}h2{font-size:19px}.screens{gap:12px}.screen{padding:3px}th,td{padding:10px 8px;font-size:12px}th:first-child{width:30%}}@media print{aside,.quick,.print,dialog{display:none!important}.layout{display:block;padding:0;max-width:none}body{background:white}.hero{background:white;color:var(--ink);border:1px solid var(--line)}.hero p,.kicker{color:var(--muted)}.chapter{box-shadow:none;break-before:page;margin:0;border:0}.screens{grid-template-columns:repeat(3,minmax(0,1fr))}.screen{max-width:180px;box-shadow:none}tr,figure{break-inside:avoid}table{font-size:11px}}
`;
const nav = chapters.map(([id,title],i)=>'<a href="#'+id+'"><span>'+String(i+1).padStart(2,'0')+'</span>'+title+'</a>').join('');
const html = '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AIPIN DVT · 功能使用说明 · v0.0.2</title><style>'+css+'</style></head><body><div class="layout"><aside><div class="wordmark">AIPIN</div><div class="edition">DVT · V1.6 协议<br>App 0.0.2+3 · 2026-09-16</div><nav>'+nav+'</nav><button class="print">打印 / 存为 PDF</button></aside><main id="top"><header class="hero"><div class="kicker">HARDWARE INTEGRATION / DVT</div><h1>DVT App<br>功能使用说明</h1><p>按页面操作核对预期结果。连接、认证、设备录音、文件归档、实时音频与固件升级。</p><div class="badges"><span>V1.6 固件协议</span><span>EVT 交互延续</span><span>Android / iOS</span><span>图片可放大 · 离线可用</span></div></header><div class="intro">图片由当前 App 的实际 Flutter 组件以示例数据生成，仅展示预期界面，不是实机通过记录。归档需配置可靠保存服务；OTA 需有效固件清单；实时音频需设备和手机满足传输容量要求。</div><div class="quick"><a href="#connect">① 连接设备</a><a href="#auth">② 安全码认证</a><a href="#record">③ 录音控制</a><a href="#files">④ 文件保存</a><a href="#archive">⑤ 归档释放</a><a href="#audio">实时音频</a><a href="#ota">固件升级</a></div>'+sections.join('')+'<footer>AIPIN DVT · 2026-09-16 · 功能操作与预期结果<br><a href="#top">返回顶部</a></footer></main></div><dialog><button class="close">关闭</button><img alt=""><p></p></dialog><script>const dialog=document.querySelector("dialog");document.querySelectorAll(".screen").forEach(b=>b.addEventListener("click",()=>{const i=b.querySelector("img");dialog.querySelector("img").src=i.src;dialog.querySelector("img").alt=i.alt;dialog.querySelector("p").textContent=i.alt;dialog.showModal()}));dialog.querySelector(".close").onclick=()=>dialog.close();dialog.addEventListener("click",e=>{if(e.target===dialog)dialog.close()});document.querySelector(".print").onclick=()=>window.print();const links=[...document.querySelectorAll("nav a")];const observer=new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting)links.forEach(a=>a.classList.toggle("active",a.hash==="#"+e.target.id))}),{rootMargin:"-5% 0px -65% 0px"});document.querySelectorAll(".chapter").forEach(s=>observer.observe(s));</script></body></html>';
await writeFile(target, html, 'utf8');
console.log(JSON.stringify({target, chapters:chapters.length, screenshots:count, bytes:Buffer.byteLength(html)}));
