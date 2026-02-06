/**
 * Weather provider using Open-Meteo (no API key). Geocode location then fetch daily forecast.
 */
import type { WeatherResult } from '@/mcp/tool-contract';

const GEOCODE_URL = 'https://geocoding-api.open-meteo.com/v1/search';
const FORECAST_URL = 'https://api.open-meteo.com/v1/forecast';

/** Map WMO weather code to short condition string. */
function weatherCodeToCondition(code: number): string {
  if (code === 0) return 'Clear';
  if (code >= 1 && code <= 3) return 'Mainly clear to cloudy';
  if (code >= 45 && code <= 48) return 'Foggy';
  if (code >= 51 && code <= 67) return 'Rain';
  if (code >= 71 && code <= 77) return 'Snow';
  if (code >= 80 && code <= 82) return 'Rain showers';
  if (code >= 85 && code <= 86) return 'Snow showers';
  if (code >= 95 && code <= 99) return 'Thunderstorm';
  return 'Variable';
}

function precipitationTypeFromCode(code: number): 'rain' | 'snow' | 'sleet' | 'none' {
  if (code >= 51 && code <= 67) return 'rain';
  if (code >= 71 && code <= 77) return 'snow';
  if (code >= 80 && code <= 82) return 'rain';
  if (code >= 85 && code <= 86) return 'snow';
  if (code >= 95 && code <= 99) return 'rain';
  return 'none';
}

export async function fetchWeather(location: string, date: string): Promise<WeatherResult> {
  const geoRes = await fetch(
    `${GEOCODE_URL}?name=${encodeURIComponent(location)}&count=1`,
    { signal: AbortSignal.timeout(10_000) },
  );
  if (!geoRes.ok) throw new Error(`Geocoding failed: ${geoRes.status}`);
  const geo = (await geoRes.json()) as { results?: Array<{ latitude: number; longitude: number; name: string }> };
  const first = geo.results?.[0];
  if (!first) throw new Error(`No location found: ${location}`);

  const lat = first.latitude;
  const lon = first.longitude;
  const resolvedName = first.name;

  const url = new URL(FORECAST_URL);
  url.searchParams.set('latitude', String(lat));
  url.searchParams.set('longitude', String(lon));
  url.searchParams.set('daily', 'temperature_2m_min,temperature_2m_max,precipitation_probability_max,weathercode');
  url.searchParams.set('timezone', 'auto');
  url.searchParams.set('start', date);
  url.searchParams.set('end', date);

  const forecastRes = await fetch(url.toString(), { signal: AbortSignal.timeout(10_000) });
  if (!forecastRes.ok) throw new Error(`Forecast failed: ${forecastRes.status}`);
  const forecast = (await forecastRes.json()) as {
    daily?: {
      time?: string[];
      temperature_2m_min?: number[];
      temperature_2m_max?: number[];
      precipitation_probability_max?: number[];
      weathercode?: number[];
    };
  };

  const daily = forecast.daily;
  if (!daily?.time?.length) throw new Error(`No forecast for date: ${date}`);

  const i = daily.time.indexOf(date);
  const idx = i >= 0 ? i : 0;
  const minC = daily.temperature_2m_min?.[idx] ?? 0;
  const maxC = daily.temperature_2m_max?.[idx] ?? 0;
  const prob = (daily.precipitation_probability_max?.[idx] ?? 0) / 100;
  const code = daily.weathercode?.[idx] ?? 0;

  return {
    location: resolvedName,
    date,
    temperature: { min: minC, max: maxC, unit: 'celsius' },
    condition: weatherCodeToCondition(code),
    precipitation: {
      type: precipitationTypeFromCode(code),
      probability: Math.min(1, Math.max(0, prob)),
    },
  };
}
