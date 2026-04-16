import Twin from '@/components/twin';

export default function Home() {
  return (
    <main className="min-h-screen bg-gray-50 flex flex-col items-center justify-center px-4 py-12">
      <div className="w-full max-w-2xl">
        <div className="text-center mb-6">
          <h1 className="text-3xl font-bold text-gray-900">AI in Production</h1>
          <p className="text-gray-500 mt-1 text-sm">Deploy your Digital Twin to the cloud</p>
        </div>

        <Twin />

        <footer className="mt-6 text-center text-xs text-gray-400">
          Week 2: Building Your Digital Twin
        </footer>
      </div>
    </main>
  );
}
