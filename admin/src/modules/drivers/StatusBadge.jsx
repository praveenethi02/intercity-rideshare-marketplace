const LABELS = {
  PENDING: 'Pending',
  APPROVED: 'Approved',
  REJECTED: 'Rejected',
};

export function StatusBadge({ status }) {
  return <span className={`dr-badge dr-badge-${String(status).toLowerCase()}`}>{LABELS[status] ?? status}</span>;
}
