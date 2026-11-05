import { STATUS_LABELS } from './usersApi';

export default function StatusBadge({ status }) {
  return (
    <span className={`us-badge us-badge-${status.toLowerCase()}`}>
      {STATUS_LABELS[status] ?? status}
    </span>
  );
}
