const LABELS = {
  NOT_SUBMITTED: 'Not submitted',
  PENDING: 'Pending',
  APPROVED: 'Approved',
  REJECTED: 'Rejected',
  UPLOADED: 'Uploaded',
  ACCEPTED: 'Accepted',
};

export function StatusBadge({ status }) {
  return <span className={`vh-badge vh-badge-${String(status).toLowerCase()}`}>{LABELS[status] ?? status}</span>;
}
