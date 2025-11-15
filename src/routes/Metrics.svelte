<script lang="ts">
	import { onMount } from 'svelte';
	import { Table } from '@flowbite-svelte-plugins/datatable';
	import { Chart } from '@flowbite-svelte-plugins/chart';
	import type { ApexOptions } from 'apexcharts';
	import { parseISO } from 'date-fns';

	let items = $state<any[]>([]);
	let isLoading = $state(true);
	let chartRendered = $state(false);

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

	const currentDate = new Date();
	const startDate1 = '2021-06-28';
	const endDate1 = '2024-03-24';
	const startDate2 = '2024-03-25';
	const endDate2 = currentDate.toISOString().split('T')[0];

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
			items = [...items, ...data.Items];
			return transformMetricsData(data);
		} catch (error) {
			console.error('Error in fetchData:', error);
			return [];
		}
	}

	function sampleData(data: TransformedMetricItem[], maxPoints = 100): TransformedMetricItem[] {
		if (data.length <= maxPoints) return data;

		const step = Math.ceil(data.length / maxPoints);
		const sampled: TransformedMetricItem[] = [];

		for (let i = 0; i < data.length; i += step) {
			sampled.push(data[i]);
		}

		if (sampled[sampled.length - 1] !== data[data.length - 1]) {
			sampled.push(data[data.length - 1]);
		}

		return sampled;
	}

	let chartOptions = $state<ApexOptions>({
		chart: {
			height: '400px',
			type: 'line',
			fontFamily: 'Inter, sans-serif',
			animations: {
				enabled: false
			},
			zoom: {
				enabled: false
			},
			toolbar: {
				show: true,
				tools: {
					download: true,
					selection: false,
					zoom: false,
					zoomin: false,
					zoomout: false,
					pan: false,
					reset: false
				}
			}
		},
		tooltip: {
			enabled: true,
			shared: false,
			intersect: false,
			x: {
				show: true
			}
		},
		dataLabels: {
			enabled: false
		},
		stroke: {
			width: 2,
			curve: 'smooth'
		},
		grid: {
			show: true,
			strokeDashArray: 4,
			padding: {
				left: 5,
				right: 5,
				top: 10
			}
		},
		series: [
			{
				name: 'Meetings',
				data: [],
				color: '#1A56DB'
			}
		],
		legend: {
			show: true
		},
		xaxis: {
			categories: [],
			labels: {
				show: true,
				style: {
					fontFamily: 'Inter, sans-serif',
					cssClass: 'text-xs font-normal fill-gray-500 dark:fill-gray-400'
				},
				rotateAlways: false,
				hideOverlappingLabels: true,
				maxHeight: 120
			},
			tickAmount: 10,
			axisBorder: {
				show: false
			},
			axisTicks: {
				show: false
			}
		},
		yaxis: {
			title: {
				text: 'Number of Meetings'
			},
			labels: {
				minWidth: 20,
				maxWidth: 70
			}
		},
		title: {
			text: 'Total Meetings in Aggregator',
			align: 'center'
		},
		markers: {
			size: 0
		},
		noData: {
			text: 'Loading data...'
		}
	});

	function updateChartOptions(data: TransformedMetricItem[]): void {
		const processedData = sampleData(data);

		const dates = processedData.map((item) => item.date);
		const meetings = processedData.map((item) => item.num_meetings);

		chartOptions = {
			...chartOptions,
			series: [
				{
					name: 'Meetings',
					data: meetings,
					color: '#1A56DB'
				}
			],
			xaxis: {
				...chartOptions.xaxis,
				categories: dates
			}
		};

		chartRendered = true;
	}

	async function loadData() {
		try {
			const dataPromises = [await fetchData(startDate1, endDate1), await fetchData(startDate2, endDate2)];
			const combinedData = (await Promise.all(dataPromises)).flat();
			updateChartOptions(combinedData);
		} catch (error) {
			console.error('Error in loadData:', error);
		} finally {
			isLoading = false;
		}
	}

	onMount(() => {
		loadData();
	});
</script>

{#if isLoading}
	<p>Loading data...</p>
{:else if items.length > 0}
	<Table {items} />
{/if}

{#if chartRendered}
	<div class="w-full mt-8">
		<Chart options={chartOptions} class="h-96" />
	</div>
{/if}
