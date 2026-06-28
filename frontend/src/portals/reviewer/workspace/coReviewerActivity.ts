export type CoReviewerActivity = 'not_started' | 'discussing' | 'reviewing' | 'submitted';

export function coReviewerActivityLabel(activity: CoReviewerActivity | string): string {
  switch (activity) {
    case 'submitted':
      return 'Submitted';
    case 'reviewing':
      return 'Reviewing';
    case 'discussing':
      return 'Discussing';
    case 'not_started':
      return 'Not started';
    default:
      return activity.replace(/_/g, ' ');
  }
}

export function coReviewerActivityVariant(
  activity: CoReviewerActivity | string
): 'success' | 'warning' | 'info' | 'neutral' {
  switch (activity) {
    case 'submitted':
      return 'success';
    case 'reviewing':
      return 'info';
    case 'discussing':
      return 'warning';
    default:
      return 'neutral';
  }
}
