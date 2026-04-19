import { SignInButton, SignedIn, SignedOut, UserButton } from '@clerk/nextjs';
import { useRouter } from 'next/router';

export default function LandingPage() {
  const router = useRouter();

  return (
    <div className="min-h-screen bg-white flex flex-col">
      {/* Header */}
      <header className="border-b border-gray-100 px-6 py-4">
        <div className="max-w-5xl mx-auto flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 bg-indigo-600 rounded-lg flex items-center justify-center">
              <span className="text-white text-sm font-bold">EF</span>
            </div>
            <span className="font-semibold text-gray-900">Essay Feedback Coach</span>
          </div>
          <div>
            <SignedOut>
              <SignInButton mode="modal">
                <button className="px-4 py-2 text-sm font-medium text-indigo-600 border border-indigo-200 rounded-lg hover:bg-indigo-50 transition-colors">
                  Sign In
                </button>
              </SignInButton>
            </SignedOut>
            <SignedIn>
              <UserButton showName={true} />
            </SignedIn>
          </div>
        </div>
      </header>

      {/* Hero */}
      <section className="bg-indigo-600 text-white py-20 px-6">
        <div className="max-w-3xl mx-auto text-center">
          <h1 className="text-4xl font-bold mb-4 leading-tight">
            Expert Essay Feedback,<br />Powered by AI
          </h1>
          <p className="text-indigo-200 text-lg mb-8 max-w-xl mx-auto">
            Get structured, actionable feedback on your essays in seconds — covering your strengths, what to improve, and a rewritten introduction to show you how.
          </p>
          <div className="flex flex-col sm:flex-row gap-3 justify-center">
            <SignedOut>
              <SignInButton mode="modal">
                <button className="px-6 py-3 bg-white text-indigo-600 font-semibold rounded-xl hover:bg-indigo-50 transition-colors">
                  Get Started Free
                </button>
              </SignInButton>
            </SignedOut>
            <SignedIn>
              <button
                onClick={() => router.push('/product')}
                className="px-6 py-3 bg-white text-indigo-600 font-semibold rounded-xl hover:bg-indigo-50 transition-colors"
              >
                Go to Essay Coach →
              </button>
            </SignedIn>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-16 px-6">
        <div className="max-w-5xl mx-auto">
          <h2 className="text-2xl font-bold text-center text-gray-900 mb-12">
            Everything you need to write better essays
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
            <div className="text-center p-6 rounded-2xl border border-gray-100 hover:shadow-sm transition-shadow">
              <div className="text-3xl mb-4">💪</div>
              <h3 className="font-semibold text-gray-900 mb-2">Strengths Analysis</h3>
              <p className="text-sm text-gray-500 leading-relaxed">
                Discover exactly what you are doing well with specific citations from your essay — not vague praise.
              </p>
            </div>
            <div className="text-center p-6 rounded-2xl border border-gray-100 hover:shadow-sm transition-shadow">
              <div className="text-3xl mb-4">🎯</div>
              <h3 className="font-semibold text-gray-900 mb-2">Actionable Improvements</h3>
              <p className="text-sm text-gray-500 leading-relaxed">
                Clear, specific fixes for each weakness — not just "be more specific" but exactly how and where.
              </p>
            </div>
            <div className="text-center p-6 rounded-2xl border border-gray-100 hover:shadow-sm transition-shadow">
              <div className="text-3xl mb-4">✏️</div>
              <h3 className="font-semibold text-gray-900 mb-2">Suggested Rewrite</h3>
              <p className="text-sm text-gray-500 leading-relaxed">
                See the improvements in action with a rewritten introduction — your ideas, better execution.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Pricing */}
      <section className="bg-gray-50 py-16 px-6">
        <div className="max-w-3xl mx-auto text-center">
          <h2 className="text-2xl font-bold text-gray-900 mb-3">Simple pricing</h2>
          <p className="text-gray-500 mb-10">Start free. Upgrade when you need more.</p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
            <div className="bg-white border border-gray-200 rounded-2xl p-6 text-left">
              <h3 className="font-bold text-gray-900 mb-1">Free</h3>
              <p className="text-3xl font-bold text-gray-900 mb-4">$0<span className="text-base font-normal text-gray-400">/mo</span></p>
              <ul className="space-y-2 text-sm text-gray-600">
                <li>✓ Sign in with Google or GitHub</li>
                <li>✓ View the landing page</li>
                <li className="text-gray-300">✗ Essay feedback</li>
              </ul>
            </div>
            <div className="bg-indigo-600 text-white rounded-2xl p-6 text-left relative">
              <span className="absolute top-3 right-3 text-xs bg-white text-indigo-600 font-semibold px-2 py-0.5 rounded-full">Popular</span>
              <h3 className="font-bold mb-1">Premium</h3>
              <p className="text-3xl font-bold mb-4">$9<span className="text-base font-normal text-indigo-300">/mo</span></p>
              <ul className="space-y-2 text-sm text-indigo-100">
                <li>✓ Unlimited essay feedback</li>
                <li>✓ All essay types supported</li>
                <li>✓ High school → graduate level</li>
                <li>✓ Suggested rewrite included</li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      <footer className="py-6 text-center text-xs text-gray-400 border-t border-gray-100">
        AIE1018 — AI Deployment &amp; MLOps · Cambrian College · Winter 2026
      </footer>
    </div>
  );
}
