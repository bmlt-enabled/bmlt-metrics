<script lang="ts">
	import { PlotlyLib } from '$lib/plotlyStore';

	import { createEventDispatcher, onMount } from 'svelte';
	const dispatch = createEventDispatcher();

	interface Props {
		// https://github.com/pjaudiomv/sveltekit-plotly
		id?: string;
		data: Array<Record<string, unknown>>;
		layout?: Record<string, unknown>;
		config?: Record<string, unknown>;
		loaded?: boolean;
		reloadPlot?: number;
		children?: import('svelte').Snippet;
		[key: string]: any;
	}

	let { id = 'plot-' + Math.floor(Math.random() * 100).toString(), data, layout = {}, config = {}, loaded = $bindable(false), reloadPlot = 0, children, ...rest }: Props = $props();

	let plotlyLib: any = $state();
	let plotNode: HTMLElement | null = null;

	function init() {
		if (!plotlyLib) plotlyLib = window.Plotly;
	}

	onMount(() => {
		const checkPlotlyLib = setInterval(() => {
			if (window.Plotly) {
				init();
				clearInterval(checkPlotlyLib);
				if (plotNode) {
					generatePlot(plotNode, data, layout, config, reloadPlot);
				}
			}
		}, 100);

		const resizeListener = () => {
			if (plotlyLib && plotNode) {
				plotlyLib.Plots.resize(plotNode);
			}
		};

		window.addEventListener('resize', resizeListener);

		return () => {
			clearInterval(checkPlotlyLib);
			window.removeEventListener('resize', resizeListener);
		};
	});

	const onHover = (d: unknown) => dispatch('hover', d);
	const onUnhover = (d: unknown) => dispatch('unhover', d);
	const onClick = (d: unknown) => dispatch('click', d);
	const onSelected = (d: unknown) => dispatch('selected', d);
	const onRelayout = (d: unknown) => dispatch('relayout', d);

	const generatePlot = (node: HTMLElement, data: Array<Record<string, unknown>>, layout: Record<string, unknown>, config: Record<string, unknown>, reloadPlot: number) => {
		if (!node || !plotlyLib) return;
		plotNode = node;
		return plotlyLib.newPlot(node, data, { ...layout }, { ...config }).then(() => {
			(node as any).on('plotly_hover', onHover);
			(node as any).on('plotly_unhover', onUnhover);
			(node as any).on('plotly_click', onClick);
			(node as any).on('plotly_selected', onSelected);
			(node as any).on('plotly_relayout', onRelayout);
			loaded = true;
		});
	};

	const updatePlot = (node: HTMLElement, data: Array<Record<string, unknown>>, layout: Record<string, unknown>, config: Record<string, unknown>, reloadPlot: number) => {
		if (!node || !plotlyLib) return;
		return plotlyLib.react(node, data, layout, config).then(() => {
			console.debug('update plotly', data);
			loaded = true;
		});
	};

	function plotlyAction(node: HTMLElement, { data, layout, config }: { data: Array<Record<string, unknown>>; layout: Record<string, unknown>; config: Record<string, unknown>; reloadPlot: number }) {
		generatePlot(node, data, layout, config, reloadPlot);

		return {
			update({ data, layout, config }: { data: Array<Record<string, unknown>>; layout: Record<string, unknown>; config: Record<string, unknown> }) {
				loaded = false;
				updatePlot(node, data, layout, config, reloadPlot);
			},
			destroy() {
				(node as any).removeListener('plotly_hover', onHover);
				(node as any).removeListener('plotly_unhover', onUnhover);
				(node as any).removeListener('plotly_click', onClick);
				(node as any).removeListener('plotly_selected', onSelected);
				(node as any).removeListener('plotly_relayout', onRelayout);
				loaded = false;
			}
		};
	}
</script>

<svelte:head>
	<script src="https://cdn.plot.ly/plotly-2.12.1.min.js" onload={init}></script>
</svelte:head>

{#if plotlyLib}
	<div {id} use:plotlyAction={{ data, layout, config, reloadPlot }} {...rest}></div>
{:else if children}{@render children()}{:else}Loading Plotly{/if}
