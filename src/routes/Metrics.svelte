<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { writable } from 'svelte/store';
	import { TableHandler, Datatable, ThSort, ThFilter } from '@vincjo/datatables';
	import Plotly from '../lib/Plotly.svelte';
	import { parseISO } from 'date-fns';

	interface MetricItem {
		date: string;
		num_meetings: string;
		num_groups: string;
		num_areas: string;
		num_regions: string;
		num_zones: string;
	}

	interface ApiResponse {
		Items: MetricItem[];
		Count: string;
		ScannedCount: string;
		LastEvaluatedKey: string;
	}

	interface TransformedMetricItem {
		date: string;
		num_meetings: number;
		num_groups: number;
		num_areas: number;
		num_regions: number;
		num_zones: number;
	}

	interface PlotData extends Record<string, unknown> {
		x: string[];
		y: number[];
		type: string;
		mode: string;
		name: string;
		hoverinfo: string;
	}

	const currentDate = new Date();
	const startDate1 = '2021-06-28';
	const endDate1 = '2024-03-24';
	const startDate2 = '2024-03-25';
	const endDate2 = currentDate.toISOString().split('T')[0];

	const table = new TableHandler<TransformedMetricItem>([], { rowsPerPage: 10 });
	const refreshPlot = writable(0);

	function transformMetricsData(data: ApiResponse): TransformedMetricItem[] {
		return data.Items.map((item) => ({
			date: item.date,
			num_meetings: parseInt(item.num_meetings, 10),
			num_groups: parseInt(item.num_groups, 10),
			num_areas: parseInt(item.num_areas, 10),
			num_regions: parseInt(item.num_regions, 10),
			num_zones: parseInt(item.num_zones, 10)
		})).sort((a, b) => parseISO(a.date).getTime() - parseISO(b.date).getTime());
	}

	async function fetchData(startDate: string, endDate: string): Promise<TransformedMetricItem[]> {
		try {
			const response = await fetch(`https://metrics.api.bmltenabled.org/metrics?start_date=${startDate}&end_date=${endDate}`, {
				method: 'GET',
				headers: {
					'Content-Type': 'application/json'
				}
			});

			if (!response.ok) {
				console.error(`Error fetching data: ${response.statusText}`);
				return [];
			}

			const data: ApiResponse = await response.json();
			return transformMetricsData(data);
		} catch (error) {
			console.error('Error in fetchData:', error);
			return [];
		}
	}

	function preparePlotData(data: TransformedMetricItem[]): { data: PlotData[] } {
		return {
			data: [
				{
					x: data.map((item) => item.date),
					y: data.map((item) => item.num_meetings),
					type: 'scatter',
					mode: 'lines',
					name: 'Meetings',
					hoverinfo: 'x+y'
				}
			]
		};
	}

	let plotData: { data: PlotData[] } = $state({
		data: []
	});

	const plotLayout = {
		title: 'Total Meetings in Aggregator',
		showlegend: true
	};

	const plotConfig = {
		scrollZoom: true
	};

	async function loadData() {
		try {
			const dataPromises = [await fetchData(startDate1, endDate1), await fetchData(startDate2, endDate2)];
			const combinedData = (await Promise.all(dataPromises)).flat();
			table.setRows(combinedData);
			plotData = preparePlotData(combinedData);
			await tick();
			refreshPlot.update((n) => n + 1);
		} catch (error) {
			console.error('Error in loadData:', error);
		}
	}

	onMount(() => {
		loadData();
	});
</script>

<Datatable basic {table}>
	<table class="dataTable">
		<thead>
			<tr>
				<ThSort {table} field="date">Date</ThSort>
				<ThSort {table} field="num_meetings">Number of Meetings</ThSort>
				<ThSort {table} field="num_groups">Number of Groups</ThSort>
				<ThSort {table} field="num_areas">Number of Areas</ThSort>
				<ThSort {table} field="num_regions">Number of Regions</ThSort>
				<ThSort {table} field="num_zones">Number of Zones</ThSort>
			</tr>
			<tr>
				<ThFilter {table} field="date" />
				<ThFilter {table} field="num_meetings" />
				<ThFilter {table} field="num_groups" />
				<ThFilter {table} field="num_areas" />
				<ThFilter {table} field="num_regions" />
				<ThFilter {table} field="num_zones" />
			</tr>
		</thead>
		<tbody>
			{#each table.rows as row (row.date)}
				<tr>
					<td>{row.date}</td>
					<td>{row.num_meetings}</td>
					<td>{row.num_groups}</td>
					<td>{row.num_areas}</td>
					<td>{row.num_regions}</td>
					<td>{row.num_zones}</td>
				</tr>
			{/each}
		</tbody>
	</table>
</Datatable>

{#if $refreshPlot}
	<Plotly data={plotData.data} layout={plotLayout} config={plotConfig} />
{/if}

<style>
	thead {
		background: #fff;
	}
	tbody td {
		border: 1px solid #f5f5f5;
		padding: 4px 20px;
	}
	tbody tr {
		transition: all, 0.2s;
	}
	tbody tr:hover {
		background: #f5f5f5;
	}
</style>
