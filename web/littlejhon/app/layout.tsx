import type { Metadata } from "next";
import { Readex_Pro } from "next/font/google";
import { Providers } from "@/app/providers";
import "./globals.css";

const readex = Readex_Pro({
  subsets: ["latin"],
  weight: ["300", "400", "500", "600", "700"],
  variable: "--font-readex",
  display: "swap",
});

export const metadata: Metadata = {
  title: "littlejohn — guard every asset",
  description:
    "we screen every tokenized-asset transfer before it settles — compliant, reserve-backed, and verified on-chain",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${readex.variable} h-full antialiased`}>
      <body className="min-h-full">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
