import type { Metadata } from 'next'

export const metadata: Metadata = {
    title: '{{APP_NAME}}',
    description: 'Built with Tano',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
    return (
        <html lang="en">
            <body style={{ fontFamily: '-apple-system, system-ui, sans-serif', margin: 0, background: '#f5f5f5' }}>
                {children}
            </body>
        </html>
    )
}
