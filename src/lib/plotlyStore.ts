import { writable } from 'svelte/store';

type PlotlyLibType = typeof window.Plotly | null;
export const PlotlyLib = writable<PlotlyLibType>(null);
