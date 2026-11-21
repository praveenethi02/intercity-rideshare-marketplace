const { z } = require('zod');
const { RATER_ROLE, RATING_RULES } = require('./rating.constants');

const paging = {
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(20),
};

// SCRUM-129 (stars) and SCRUM-130 (review). An empty review after trimming is saved as null.
const createRating = z.strictObject({
  tripId: z.uuid(),
  rateeId: z.uuid(),
  stars: z.number().int().min(RATING_RULES.MIN_STARS).max(RATING_RULES.MAX_STARS),
  review: z.string().trim().max(RATING_RULES.MAX_REVIEW_LENGTH).nullable().optional(),
});

const userIdParams = z.strictObject({ userId: z.uuid() });

// role: the rated user's part in the trip. DRIVER lists the ratings passengers gave them as a driver.
const receivedQuery = z.strictObject({
  role: z.enum(Object.values(RATER_ROLE)).optional(),
  ...paging,
});

const mineQuery = z.strictObject({ ...paging });

module.exports = { createRating, userIdParams, receivedQuery, mineQuery };
