'use client';

import { useState } from 'react';
import { useAuth, Protect, UserButton, PricingTable } from '@clerk/nextjs';
import { fetchEventSource } from '@microsoft/fetch-event-source';
import ReactMarkdown from 'react-markdown';

interface FormState {
  essayText:       string;
  assignmentBrief: string;
  essayType:       string;
  educationLevel:  string;
  wordLimit:       string;
}

const EMPTY: FormState = {
  essayText:       '',
  assignmentBrief: '',
  essayType:       'argumentative',
  educationLevel:  'undergraduate',
  wordLimit:       '',
};

function EssayForm() {
  const { getToken } = useAuth();
  const [form, setForm]       = useState<FormState>(EMPTY);
  const [output, setOutput]   = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError]     = useState('');

  const handleChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>
  ) => setForm(prev => ({ ...prev, [e.target.name]: e.target.value }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.essayText.trim() || !form.assignmentBrief.trim()) return;

    setLoading(true);
    setOutput('');
    setError('');

    const token = await getToken();

    const body = {
      essay_text:       form.essayText,
      assignment_brief: form.assignmentBrief,
      essay_type:       form.essayType,
      education_level:  form.educationLevel,
      word_limit:       form.wordLimit ? parseInt(form.wordLimit, 10) : null,
    };

    let buffer = '';

    try {
      await fetchEventSource(
        `${process.env.NEXT_PUBLIC_API_URL || ''}/api`,
        {
          method: 'POST',
          headers: {
            'Content-Type':  'application/json',
            'Authorization': `Bearer ${token}`,
          },
          body: JSON.stringify(body),
          onmessage(event) {
            buffer += event.data + '\n';
            setOutput(buffer);
          },
          onerror(err) {
            setError('Something went wrong. Please try again.');
            setLoading(false);
            throw err;
          },
          onclose() {
            setLoading(false);
          },
        }
      );
    } catch {
      setLoading(false);
    }
  };

  const reset = () => { setForm(EMPTY); setOutput(''); setError(''); };

  return (
    <div className="w-full max-w-3xl mx-auto space-y-6">
      {/* Form */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-200">
        <div className="px-6 py-4 border-b border-gray-100 flex items-center justify-between">
          <div>
            <h2 className="text-base font-semibold text-gray-900">Submit Your Essay</h2>
            <p className="text-xs text-gray-400 mt-0.5">Fill in all fields then click Get Feedback</p>
          </div>
          {output && (
            <button onClick={reset} className="text-xs text-gray-400 hover:text-gray-600 transition-colors">
              Start over
            </button>
          )}
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-5">
          {/* Dropdowns + word limit */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1.5">Essay Type</label>
              <select
                name="essayType" value={form.essayType} onChange={handleChange} disabled={loading}
                className="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500 bg-white text-gray-800 disabled:opacity-60"
              >
                <option value="argumentative">Argumentative</option>
                <option value="descriptive">Descriptive</option>
                <option value="expository">Expository</option>
                <option value="narrative">Narrative</option>
                <option value="analytical">Analytical</option>
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1.5">Education Level</label>
              <select
                name="educationLevel" value={form.educationLevel} onChange={handleChange} disabled={loading}
                className="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500 bg-white text-gray-800 disabled:opacity-60"
              >
                <option value="high_school">High School</option>
                <option value="undergraduate">Undergraduate</option>
                <option value="graduate">Graduate</option>
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1.5">
                Word Limit <span className="text-gray-400 font-normal">(optional)</span>
              </label>
              <input
                type="number" name="wordLimit" value={form.wordLimit} onChange={handleChange}
                disabled={loading} placeholder="e.g. 1000" min={50}
                className="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500 text-gray-800 placeholder-gray-400 disabled:opacity-60"
              />
            </div>
          </div>

          {/* Assignment Brief */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1.5">
              Assignment Brief <span className="text-red-400">*</span>
            </label>
            <textarea
              name="assignmentBrief" value={form.assignmentBrief} onChange={handleChange}
              disabled={loading} required rows={3}
              placeholder="What did the assignment ask you to write about?"
              className="w-full px-4 py-3 text-sm border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-500 text-gray-800 placeholder-gray-400 resize-none disabled:opacity-60"
            />
          </div>

          {/* Essay Text */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1.5">
              Your Essay <span className="text-red-400">*</span>
            </label>
            <textarea
              name="essayText" value={form.essayText} onChange={handleChange}
              disabled={loading} required minLength={50} rows={12}
              placeholder="Paste your full essay here..."
              className="w-full px-4 py-3 text-sm border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-500 text-gray-800 placeholder-gray-400 resize-y disabled:opacity-60"
            />
            <p className="mt-1 text-xs text-gray-400">
              {form.essayText.trim().split(/\s+/).filter(Boolean).length} words
            </p>
          </div>

          {error && (
            <div className="px-4 py-3 bg-red-50 border border-red-100 rounded-xl text-sm text-red-600">{error}</div>
          )}

          <button
            type="submit"
            disabled={loading || !form.essayText.trim() || !form.assignmentBrief.trim()}
            className="w-full py-3 px-6 bg-indigo-600 text-white text-sm font-medium rounded-xl hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {loading ? 'Analysing your essay…' : 'Get Feedback'}
          </button>
        </form>
      </div>

      {/* Streaming Output */}
      {output && (
        <div className="bg-white rounded-2xl shadow-sm border border-gray-200">
          <div className="px-6 py-4 border-b border-gray-100 flex items-center gap-2">
            <div className={`w-2 h-2 rounded-full ${loading ? 'bg-yellow-400 animate-pulse' : 'bg-green-500'}`} />
            <span className="text-sm font-medium text-gray-700">
              {loading ? 'Generating feedback…' : 'Feedback ready'}
            </span>
          </div>
          <div className="px-6 py-5 text-sm text-gray-800 markdown">
            <ReactMarkdown>{output}</ReactMarkdown>
          </div>
        </div>
      )}
    </div>
  );
}

export default function ProductPage() {
  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white border-b border-gray-100 px-6 py-4">
        <div className="max-w-3xl mx-auto flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="w-7 h-7 bg-indigo-600 rounded-md flex items-center justify-center">
              <span className="text-white text-xs font-bold">EF</span>
            </div>
            <span className="font-semibold text-gray-900 text-sm">Essay Feedback Coach</span>
          </div>
          <UserButton showName={true} />
        </div>
      </header>

      {/* Subscription gate: show pricing table to non-Premium users */}
      <Protect
        condition={(has) => has({ plan: 'premium_subscription' })}
        fallback={
          <div className="max-w-2xl mx-auto px-4 py-16 text-center">
            <h2 className="text-xl font-bold text-gray-900 mb-2">Premium required</h2>
            <p className="text-gray-500 mb-8 text-sm">
              Subscribe to access the Essay Feedback Coach.
            </p>
            <PricingTable />
          </div>
        }
      >
        <main className="py-10 px-4">
          <EssayForm />
        </main>
      </Protect>
    </div>
  );
}
