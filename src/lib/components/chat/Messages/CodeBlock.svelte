<script lang="ts">
	import hljs from 'highlight.js';
	import { toast } from 'svelte-sonner';
	import { getContext, onMount, tick, onDestroy } from 'svelte';
	import { config, theme, pyodideWorker as pyodideWorkerStore } from '$lib/stores';

	import { createPyodideWorker } from '$lib/pyodide/createPyodideWorker';
	import { executeCode } from '$lib/apis/utils';
	import {
		copyToClipboard,
		initMermaid,
		renderMermaidDiagram,
		renderVegaVisualization,
		unescapeHtml
	} from '$lib/utils';

	import 'highlight.js/styles/github-dark.min.css';
	import equal from 'fast-deep-equal';

	import CodeEditor from '$lib/components/common/CodeEditor.svelte';
	import SvgPanZoom from '$lib/components/common/SVGPanZoom.svelte';

	import ChevronUp from '$lib/components/icons/ChevronUp.svelte';
	import ChevronUpDown from '$lib/components/icons/ChevronUpDown.svelte';
	import CommandLine from '$lib/components/icons/CommandLine.svelte';
	import Cube from '$lib/components/icons/Cube.svelte';
	import Tooltip from '$lib/components/common/Tooltip.svelte';

	const i18n = getContext('i18n');

	export let id = '';
	export let edit = true;

	export let onSave = (e) => {};
	export let onUpdate = (e, codeBlockId = '') => {};
	export let onPreview = (e) => {};

	export let save = false;
	export let run = true;
	export let preview = false;
	export let collapsed = false;

	export let token;
	export let lang = '';

	// CRUZ BRAND PATCH: true when this block is rendered as a live chart inline
	// (see the iframe further down). When it is, the source is suppressed --
	// otherwise the reader gets a chart with a wall of HTML stacked beneath it,
	// and "Expand" reveals code rather than enlarging the chart. Use the Preview
	// button for a larger view.
	//
	// Matched on the closing markup rather than the fence language alone: models
	// label SVG as svg, xml, svg+xml or nothing at all, and an unrecognised label
	// meant the chart silently fell back to a collapsed code block. The language
	// list still gates it so that a *program* which happens to print '</svg>'
	// keeps its source and its Run button.
	const CRUZ_ARTIFACT_LANGS = ['', 'html', 'svg', 'xml', 'svg+xml', 'image/svg+xml'];
	$: cruzInlineArtifact =
		CRUZ_ARTIFACT_LANGS.includes((lang ?? '').toLowerCase()) &&
		(code.includes('</html>') || code.includes('</svg>'));

	// The frame is sandboxed, so prefers-color-scheme inside it follows the OS
	// while the frame's own background follows the app theme (bg-white
	// dark:bg-black, below). Those two disagree on a light-themed machine running
	// Cruz in dark mode, which rendered dark text on a black background -- an
	// invisible chart with no error. The app theme is the one that colours the
	// frame, so it is the one that decides the ink. Read from the document rather
	// than from the theme name because 'system' resolves to a class at runtime,
	// and because the class is literally what drives the frame's background.
	// $theme is passed in only so this recomputes when the user switches themes;
	// both theme setters apply the class synchronously, so it is already in place
	// by the time this reactive statement flushes.
	const cruzInk = (_theme: string) =>
		typeof document !== 'undefined' && !document.documentElement.classList.contains('dark')
			? '#3A3A46'
			: '#E8E8F0';
	$: cruzArtifactInk = cruzInk($theme);

	// SVG clips anything outside its viewBox, silently. Generated charts routinely
	// place long axis labels just outside it, so text disappears with no error and
	// it reads as a rendering bug. Prompting alone does not reliably prevent this,
	// so the frame document is fixed up here instead: overflow:visible stops the
	// clipping, and the padded, scrolling wrapper guarantees whatever spills out
	// is still reachable.
	//
	// The text rule is a floor, not an override, and its weight is chosen with care.
	// A fill="..." presentation attribute loses to any author stylesheet, so a
	// hard-coded dark label still gets themed and cannot vanish against the frame.
	// A chart that themes itself -- which the model prompt asks for, via a
	// prefers-color-scheme media query -- declares 'text' at the same specificity
	// but later in the document, so its own colours win. Hence bare 'text' rather
	// than 'svg text', and hence the stylesheet goes in at the TOP of <head>:
	// injecting it before </head> would have placed it after the chart's own
	// styles and silently overruled them.
	const cruzArtifactCss = (ink: string) => `
<style>
  html, body { margin:0; padding:0; background:transparent; overflow:visible; color:${ink}; }
  body { padding:14px 18px; box-sizing:border-box;
         font-family:'Space Grotesk', ui-sans-serif, system-ui, sans-serif; }
  svg { overflow: visible !important; max-width:100%; height:auto; display:block; }
  text { fill: ${ink}; }
  .grid, .axis { stroke: ${ink}; opacity: 0.18; }
  .wrap, .container { max-width:100% !important; }
</style>`;

	$: cruzArtifactDoc = !cruzInlineArtifact
		? ''
		: code.includes('<head>')
			? code.replace('<head>', `<head>${cruzArtifactCss(cruzArtifactInk)}`)
			: cruzArtifactCss(cruzArtifactInk) + code;

	let cruzArtifactFrame: HTMLIFrameElement;

	const cruzFullscreen = () => {
		const el: any = cruzArtifactFrame?.parentElement ?? cruzArtifactFrame;
		if (!el) return;
		if (document.fullscreenElement) {
			document.exitFullscreen?.();
		} else {
			(el.requestFullscreen ?? el.webkitRequestFullscreen ?? el.msRequestFullscreen)?.call(el);
		}
	};
	export let code = '';
	export let attributes = {};

	export let className = '';
	export let editorClassName = '';
	export let stickyButtonsClassName = 'top-0';

	let localPyodideWorker = null;

	let _code = '';
	$: if (code) {
		updateCode();
	}

	const updateCode = () => {
		_code = code;
	};

	let _token = null;

	let renderHTML = null;
	let renderError = null;

	let highlightedCode = null;
	let executing = false;

	let stdout = null;
	let stderr = null;
	let result = null;
	let files = null;

	let copied = false;
	let saved = false;

	const collapseCodeBlock = () => {
		collapsed = !collapsed;
	};

	const saveCode = () => {
		saved = true;

		code = _code;
		onSave(code);

		setTimeout(() => {
			saved = false;
		}, 1000);
	};

	const copyCode = async () => {
		copied = true;
		await copyToClipboard(_code);

		setTimeout(() => {
			copied = false;
		}, 1000);
	};

	const previewCode = () => {
		onPreview(code);
	};

	const checkPythonCode = (str) => {
		// Check if the string contains typical Python syntax characters
		const pythonSyntax = [
			'def ',
			'else:',
			'elif ',
			'try:',
			'except:',
			'finally:',
			'yield ',
			'lambda ',
			'assert ',
			'nonlocal ',
			'del ',
			'True',
			'False',
			'None',
			' and ',
			' or ',
			' not ',
			' in ',
			' is ',
			' with '
		];

		for (let syntax of pythonSyntax) {
			if (str.includes(syntax)) {
				return true;
			}
		}

		// If none of the above conditions met, it's probably not Python code
		return false;
	};

	const executePython = async (code) => {
		result = null;
		stdout = null;
		stderr = null;

		executing = true;

		if ($config?.code?.engine === 'jupyter') {
			const output = await executeCode(localStorage.token, code).catch((error) => {
				toast.error(`${error}`);
				return null;
			});

			if (output) {
				if (output['stdout']) {
					stdout = output['stdout'];
					const stdoutLines = stdout.split('\n');

					for (const [idx, line] of stdoutLines.entries()) {
						if (line.startsWith('data:image/png;base64')) {
							if (files) {
								files.push({
									type: 'image/png',
									data: line
								});
							} else {
								files = [
									{
										type: 'image/png',
										data: line
									}
								];
							}

							if (stdout.includes(`${line}\n`)) {
								stdout = stdout.replace(`${line}\n`, ``);
							} else if (stdout.includes(`${line}`)) {
								stdout = stdout.replace(`${line}`, ``);
							}
						}
					}
				}

				if (output['result']) {
					result = output['result'];
					const resultLines = result.split('\n');

					for (const [idx, line] of resultLines.entries()) {
						if (line.startsWith('data:image/png;base64')) {
							if (files) {
								files.push({
									type: 'image/png',
									data: line
								});
							} else {
								files = [
									{
										type: 'image/png',
										data: line
									}
								];
							}

							if (result.includes(`${line}\n`)) {
								result = result.replace(`${line}\n`, ``);
							} else if (result.includes(`${line}`)) {
								result = result.replace(`${line}`, ``);
							}
						}
					}
				}

				output['stderr'] && (stderr = output['stderr']);
			}

			executing = false;
		} else {
			executePythonAsWorker(code);
		}
	};

	const executePythonAsWorker = async (code) => {
		let packages = [
			/\bimport\s+requests\b|\bfrom\s+requests\b/.test(code) ? 'requests' : null,
			/\bimport\s+bs4\b|\bfrom\s+bs4\b/.test(code) ? 'beautifulsoup4' : null,
			/\bimport\s+numpy\b|\bfrom\s+numpy\b/.test(code) ? 'numpy' : null,
			/\bimport\s+pandas\b|\bfrom\s+pandas\b/.test(code) ? 'pandas' : null,
			/\bimport\s+matplotlib\b|\bfrom\s+matplotlib\b/.test(code) ? 'matplotlib' : null,
			/\bimport\s+seaborn\b|\bfrom\s+seaborn\b/.test(code) ? 'seaborn' : null,
			/\bimport\s+sklearn\b|\bfrom\s+sklearn\b/.test(code) ? 'scikit-learn' : null,
			/\bimport\s+scipy\b|\bfrom\s+scipy\b/.test(code) ? 'scipy' : null,
			/\bimport\s+re\b|\bfrom\s+re\b/.test(code) ? 'regex' : null,
			/\bimport\s+seaborn\b|\bfrom\s+seaborn\b/.test(code) ? 'seaborn' : null,
			/\bimport\s+sympy\b|\bfrom\s+sympy\b/.test(code) ? 'sympy' : null,
			/\bimport\s+tiktoken\b|\bfrom\s+tiktoken\b/.test(code) ? 'tiktoken' : null,
			/\bimport\s+pytz\b|\bfrom\s+pytz\b/.test(code) ? 'pytz' : null
		].filter(Boolean);

		console.log(packages);

		// Reuse the shared Pyodide worker when code interpreter is active,
		// so files written here are immediately visible in PyodideFileNav.
		// Otherwise fall back to a throwaway worker.
		const sharedWorker = $pyodideWorkerStore;
		const isShared = !!sharedWorker;
		const worker = sharedWorker ?? createPyodideWorker();

		if (!isShared) {
			localPyodideWorker = worker;
		}

		worker.postMessage({
			id: id,
			code: code,
			packages: packages
		});

		const timeoutId = setTimeout(() => {
			if (executing) {
				executing = false;
				stderr = 'Execution Time Limit Exceeded';
				if (!isShared) {
					worker.terminate();
					localPyodideWorker = null;
				}
			}
		}, 60000);

		const handler = (event) => {
			// Ignore messages from other requests on the shared worker
			if (event.data?.id !== id) return;

			console.log('pyodideWorker.onmessage', event);
			const { id: _id, ...data } = event.data;

			console.log(_id, data);

			if (data['stdout']) {
				stdout = data['stdout'];
				const stdoutLines = stdout.split('\n');

				for (const [idx, line] of stdoutLines.entries()) {
					if (line.startsWith('data:image/png;base64')) {
						if (files) {
							files.push({
								type: 'image/png',
								data: line
							});
						} else {
							files = [
								{
									type: 'image/png',
									data: line
								}
							];
						}

						if (stdout.includes(`${line}\n`)) {
							stdout = stdout.replace(`${line}\n`, ``);
						} else if (stdout.includes(`${line}`)) {
							stdout = stdout.replace(`${line}`, ``);
						}
					}
				}
			}

			if (data['result']) {
				result = data['result'];
				const resultLines = result.split('\n');

				for (const [idx, line] of resultLines.entries()) {
					if (line.startsWith('data:image/png;base64')) {
						if (files) {
							files.push({
								type: 'image/png',
								data: line
							});
						} else {
							files = [
								{
									type: 'image/png',
									data: line
								}
							];
						}

						if (result.startsWith(`${line}\n`)) {
							result = result.replace(`${line}\n`, ``);
						} else if (result.startsWith(`${line}`)) {
							result = result.replace(`${line}`, ``);
						}
					}
				}
			}

			data['stderr'] && (stderr = data['stderr']);
			data['result'] && (result = data['result']);

			clearTimeout(timeoutId);
			worker.removeEventListener('message', handler);
			executing = false;

			// Signal PyodideFileNav to auto-refresh after execution
			window.dispatchEvent(new Event('pyodide:files'));
		};

		worker.addEventListener('message', handler);

		worker.onerror = (event) => {
			console.log('pyodideWorker.onerror', event);
			clearTimeout(timeoutId);
			worker.removeEventListener('message', handler);
			executing = false;
		};
	};

	let mermaid = null;
	const renderMermaid = async (code) => {
		if (!mermaid) {
			mermaid = await initMermaid();
		}
		return await renderMermaidDiagram(mermaid, code);
	};

	const render = async () => {
		onUpdate(token, id);
		if (lang === 'mermaid' && (token?.raw ?? '').slice(-4).includes('```')) {
			try {
				renderHTML = await renderMermaid(code);
			} catch (error) {
				console.error('Failed to render mermaid diagram:', error);
				const errorMsg = error instanceof Error ? error.message : String(error);
				renderError = $i18n.t('Failed to render diagram') + `: ${errorMsg}`;
				renderHTML = null;
			}
		} else if (
			(lang === 'vega' || lang === 'vega-lite') &&
			(token?.raw ?? '').slice(-4).includes('```')
		) {
			try {
				renderHTML = await renderVegaVisualization(code, lang);
			} catch (error) {
				console.error('Failed to render Vega visualization:', error);
				const errorMsg = error instanceof Error ? error.message : String(error);
				renderError = $i18n.t('Failed to render visualization') + `: ${errorMsg}`;
				renderHTML = null;
			}
		}
	};

	$: if (token) {
		if (token.text !== _token?.text || token.raw !== _token?.raw) {
			_token = token;
		} else if (!equal(token, _token)) {
			_token = token;
		}
	}

	$: if (_token) {
		render();
	}

	$: if (attributes) {
		onAttributesUpdate();
	}

	const onAttributesUpdate = () => {
		if (attributes?.output) {
			try {
				const output = JSON.parse(unescapeHtml(attributes.output));
				stdout = output.stdout;
				stderr = output.stderr;
				result = output.result;
			} catch (error) {
				console.error('Error:', error);
			}
		}
	};

	onMount(async () => {
		if (token) {
			onUpdate(token, id);
		}
	});

	onDestroy(() => {
		if (localPyodideWorker) {
			localPyodideWorker.terminate();
			localPyodideWorker = null;
		}
	});
</script>

<div>
	<div
		class="relative {className} flex flex-col rounded-2xl border border-gray-100/30 dark:border-gray-850/30 my-0.5"
		dir="ltr"
	>
		{#if ['mermaid', 'vega', 'vega-lite'].includes(lang)}
			{#if renderHTML}
				<SvgPanZoom
					className=" rounded-2xl max-h-fit overflow-hidden"
					svg={renderHTML}
					content={_token.text}
				/>
			{:else}
				<div class="p-3">
					{#if renderError}
						<div
							class="flex gap-2.5 border px-4 py-3 border-red-600/10 bg-red-600/10 rounded-2xl mb-2"
						>
							{renderError}
						</div>
					{/if}
					<pre>{code}</pre>
				</div>
			{/if}
		{:else}
			<div
				class="sticky {stickyButtonsClassName} left-0 right-0 py-1.5 px-3.5 gap-2 flex items-center justify-end w-full z-10 text-xs text-black dark:text-white bg-white dark:bg-black rounded-t-2xl"
			>
				<div class="flex-1 truncate">
					<Tooltip content={lang} placement="top-start">
						<span class=" truncate text-ellipsis">
							{lang}
						</span>
					</Tooltip>
				</div>

				<div class="flex items-center gap-0.5 shrink-0">
					<button
						class="flex gap-1 items-center bg-none border-none transition rounded-md px-1.5 py-0.5 bg-white dark:bg-black"
						on:click={collapseCodeBlock}
					>
						<div class=" -translate-y-[0.5px]">
							<ChevronUpDown className="size-3" />
						</div>

						<div>
							{collapsed ? $i18n.t('Expand') : $i18n.t('Collapse')}
						</div>
					</button>

					{#if ($config?.features?.enable_code_execution ?? true) && (lang.toLowerCase() === 'python' || lang.toLowerCase() === 'py' || (lang === '' && checkPythonCode(code)))}
						{#if executing}
							<div
								class="run-code-button bg-none border-none p-0.5 cursor-not-allowed bg-white dark:bg-black"
							>
								{$i18n.t('Running')}
							</div>
						{:else if run}
							<button
								class="flex gap-1 items-center run-code-button bg-none border-none transition rounded-md px-1.5 py-0.5 bg-white dark:bg-black"
								on:click={async () => {
									code = _code;
									await tick();
									executePython(code);
								}}
							>
								<div>
									{$i18n.t('Run')}
								</div>
							</button>
						{/if}
					{/if}

					{#if save}
						<button
							class="save-code-button bg-none border-none transition rounded-md px-1.5 py-0.5 bg-white dark:bg-black"
							on:click={saveCode}
						>
							{saved ? $i18n.t('Saved') : $i18n.t('Save')}
						</button>
					{/if}

					<button
						class="copy-code-button bg-none border-none transition rounded-md px-1.5 py-0.5 bg-white dark:bg-black"
						on:click={copyCode}>{copied ? $i18n.t('Copied') : $i18n.t('Copy')}</button
					>

					<!-- CRUZ BRAND PATCH: same widened match as the inline render, so an
					     SVG fenced as xml (or unfenced) still offers the side panel. -->
					{#if preview && (cruzInlineArtifact || ['html', 'svg'].includes(lang))}
						<button
							class="flex gap-1 items-center run-code-button bg-none border-none transition rounded-md px-1.5 py-0.5 bg-white dark:bg-black"
							on:click={previewCode}
						>
							<div>
								{$i18n.t('Preview')}
							</div>
						</button>
					{/if}
				</div>
			</div>

			<div
				class="language-{lang} rounded-t-2xl -mt-8 {editorClassName
					? editorClassName
					: executing || stdout || stderr || result
						? ''
						: 'rounded-b-2xl'} overflow-hidden"
			>
				<div class=" pt-6.5 bg-white dark:bg-black"></div>

				{#if cruzInlineArtifact}
					<!-- CRUZ BRAND PATCH: chart renders below; source intentionally hidden. -->
				{:else if !collapsed}
					{#if edit}
						<CodeEditor
							value={code}
							{id}
							{lang}
							onSave={() => {
								saveCode();
							}}
							onChange={(value) => {
								_code = value;
							}}
						/>
					{:else}
						<pre
							class=" hljs p-4 px-5 overflow-x-auto"
							style="border-top-left-radius: 0px; border-top-right-radius: 0px; {(executing ||
								stdout ||
								stderr ||
								result) &&
								'border-bottom-left-radius: 0px; border-bottom-right-radius: 0px;'}"><code
								class="language-{lang} rounded-t-none whitespace-pre text-sm"
								>{#if lang && hljs.getLanguage(lang)}{@html hljs.highlight(code, {
										language: lang,
										ignoreIllegals: true
									}).value}{:else}{code}{/if}</code
							></pre>
					{/if}
				{:else}
					<div
						class="bg-white dark:bg-black dark:text-white rounded-b-2xl! pt-1 pb-2 px-4 flex flex-col gap-2 text-xs"
					>
						<span class="text-gray-500 italic">
							{$i18n.t('{{COUNT}} hidden lines', {
								COUNT: code.split('\n').length
							})}
						</span>
					</div>
				{/if}
			</div>

			<!--
				CRUZ BRAND PATCH: render html/svg inline, in the conversation.
				Upstream only offers "Preview", which opens the side artifact panel --
				so a chart is either invisible or off to one side. Claude renders it in
				the message flow, which is what people expect of a chart.

				Gated on closing markup so a partially-streamed document does not
				flicker on every token. sandbox="allow-scripts" WITHOUT
				allow-same-origin is deliberate: scripts run, but the frame cannot
				reach the parent document, cookies or session. Do not add
				allow-same-origin here.
			-->
			{#if cruzInlineArtifact}
				<div class="cruz-artifact-wrap relative">
					<iframe
						bind:this={cruzArtifactFrame}
						title={$i18n.t('Preview')}
						class="cruz-inline-artifact w-full border-0 bg-white dark:bg-black"
						sandbox="allow-scripts"
						srcdoc={cruzArtifactDoc}
					></iframe>

					<!--
						Upstream's "Expand" only toggles the source, which is hidden for
						artifacts -- so it appeared to do nothing. This puts the chart
						itself into real fullscreen instead.
					-->
					<button
						class="cruz-artifact-fullscreen absolute top-2 right-2 rounded-lg px-2 py-1 text-xs"
						title={$i18n.t('Fullscreen')}
						on:click={cruzFullscreen}
					>
						⤢
					</button>
				</div>
			{/if}

			{#if !collapsed}
				<div
					id="plt-canvas-{id}"
					class="bg-gray-50 dark:bg-black dark:text-white max-w-full overflow-x-auto scrollbar-hidden"
				/>

				{#if executing || stdout || stderr || result || files}
					<div
						class="bg-gray-50 dark:bg-black dark:text-white rounded-b-2xl! pt-2 pb-3 px-3.5 flex flex-col gap-2"
					>
						{#if executing}
							<div class=" ">
								<div class=" text-gray-500 text-xs mb-1">{$i18n.t('STDOUT/STDERR')}</div>
								<div class="text-sm">{$i18n.t('Running...')}</div>
							</div>
						{:else}
							{#if stdout || stderr}
								<div class=" ">
									<div class=" text-gray-500 text-xs mb-1">{$i18n.t('STDOUT/STDERR')}</div>
									<div
										class="text-sm font-mono whitespace-pre-wrap {stdout?.split('\n')?.length > 100
											? `max-h-96`
											: ''}  overflow-y-auto"
									>
										{stdout || stderr}
									</div>
								</div>
							{/if}
							{#if result || files}
								<div class=" ">
									<div class=" text-gray-500 text-xs mb-1">{$i18n.t('RESULT')}</div>
									{#if result}
										<div class="text-sm">{`${JSON.stringify(result)}`}</div>
									{/if}
									{#if files}
										<div class="flex flex-col gap-2">
											{#each files as file}
												{#if file.type.startsWith('image')}
													<img src={file.data} alt="Output" class=" w-full max-w-[36rem]" />
												{/if}
											{/each}
										</div>
									{/if}
								</div>
							{/if}
						{/if}
					</div>
				{/if}
			{/if}
		{/if}
	</div>
</div>
