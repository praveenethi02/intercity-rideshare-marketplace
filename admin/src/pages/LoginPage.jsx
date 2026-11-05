import { useState } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { errorMessage } from '../lib/api';
import { isAdmin, login, useSession } from '../lib/auth';

export default function LoginPage() {
  const session = useSession();
  const location = useLocation();
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);

  if (isAdmin(session)) {
    return <Navigate to={location.state?.from || '/'} replace />;
  }

  async function handleSubmit(event) {
    event.preventDefault();
    setError('');
    setSubmitting(true);
    try {
      await login(phone, password);
    } catch (err) {
      setError(err.response ? errorMessage(err) : err.message);
      setSubmitting(false);
    }
  }

  return (
    <div className="login">
      <form className="login-card" onSubmit={handleSubmit}>
        <h1>Rideshare Admin</h1>
        <p className="muted">Log in with your administrator account.</p>

        {error && (
          <p className="alert" role="alert">
            {error}
          </p>
        )}

        <label>
          Phone number
          <input
            type="tel"
            autoComplete="username"
            placeholder="07X XXX XXXX"
            value={phone}
            onChange={(event) => setPhone(event.target.value)}
            required
          />
        </label>

        <label>
          Password
          <input
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
          />
        </label>

        <button type="submit" className="button button-primary" disabled={submitting}>
          {submitting ? 'Logging in…' : 'Log in'}
        </button>
      </form>
    </div>
  );
}
