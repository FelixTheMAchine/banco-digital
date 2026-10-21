import React from "react";
import { View, Text } from "react-native";
import Svg, { Line, Path, Circle } from "react-native-svg";
import { formatCents } from "../lib/money";
import { usePalette } from "./ui";

export function BalanceChart({ data }: { data: { label: string; cents: number }[] }) {
  const c = usePalette();
  if (!data.length) return <Text style={{ color: c.muted }}>A evolução aparecerá após as primeiras movimentações.</Text>;
  const max = Math.max(...data.map(point => point.cents), 1);
  const min = Math.min(...data.map(point => point.cents), 0);
  // Números fracionários abaixo são somente coordenadas visuais, nunca saldos persistidos.
  const points = data.map((point, index) => ({ x: 12 + index / Math.max(1, data.length - 1) * 276, y: 120 - (point.cents - min) / Math.max(1, max - min) * 100 }));
  const path = points.map((point, index) => `${index ? "L" : "M"}${point.x},${point.y}`).join(" ");
  return <View accessible accessibilityLabel={`Evolução: ${data.map(point => `${point.label}: ${formatCents(point.cents)}`).join(". ")}`}><Svg width="100%" height={145} viewBox="0 0 300 145"><Line x1={12} y1={122} x2={288} y2={122} stroke={c.border} /><Path d={path} fill="none" stroke={c.accent} strokeWidth={3} />{points.map((point, index) => <Circle key={index} cx={point.x} cy={point.y} r={3} fill={c.accent} />)}</Svg><View style={{ flexDirection: "row", justifyContent: "space-between" }}><Text style={{ color: c.muted, fontSize: 12 }}>{data[0].label}</Text><Text style={{ color: c.muted, fontSize: 12 }}>{data[data.length - 1].label}</Text></View></View>;
}
