/**
 * Cloud Function to send email when user submits feedback
 *
 * Listens for new documents in users/{userId}/issue_reports/{reportId}
 * and sends an email to badyaapp@gmail.com with the feedback details.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as nodemailer from "nodemailer";
import * as dotenv from "dotenv";

// Load environment variables from .env file (for local development)
dotenv.config();

// Gmail credentials from .env file or environment variables
const gmailUser = process.env.GMAIL_USER || "badyaapp@gmail.com";
const gmailPass = process.env.GMAIL_PASS;

// Create nodemailer transporter
const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
        user: gmailUser,
        pass: gmailPass,
    },
});

/**
 * Cloud Function triggered when a new feedback document is created
 */
export const sendFeedbackEmail = onDocumentCreated(
    {
        document: "users/{userId}/issue_reports/{reportId}",
        region: "us-central1",
        maxInstances: 5,
    },
    async (event) => {
        // Skip if Gmail credentials are not configured
        if (!gmailUser || !gmailPass) {
            logger.warn(
                "Skipping feedback email; Gmail credentials not configured. " +
                "Please set GMAIL_USER and GMAIL_PASS in .env file or as environment variables."
            );
            return;
        }

        const snap = event.data;
        if (!snap) {
            logger.warn("No document data in feedback event");
            return;
        }

        const data = snap.data() as {
            category?: string;
            description?: string;
            user_email?: string;
            user_display_name?: string;
        };

        const { category, description, user_email, user_display_name } = data;
        const { userId, reportId } = event.params;

        // Build email subject
        const subject = `[Badya Feedback] ${category ?? "General"}`;

        // Build email body with user info and feedback
        const bodyLines = [
            `User ID: ${userId}`,
            `Report ID: ${reportId}`,
            `Name: ${user_display_name || "(unknown)"}`,
            `Email: ${user_email || "(unknown)"}`,
            "",
            "Feedback:",
            description || "(no description provided)",
        ];

        // Send email to badyaapp@gmail.com with feedback details
        const adminMailOptions = {
            from: gmailUser,
            to: "badyaapp@gmail.com",
            replyTo: user_email || gmailUser, // Reply goes to the user who sent feedback
            subject,
            text: bodyLines.join("\n"),
        };

        try {
            await transporter.sendMail(adminMailOptions);
            logger.info(`Feedback email sent to admin successfully for report ${reportId}`);
        } catch (error) {
            logger.error(`Error sending feedback email to admin: ${error}`);
            // Don't throw - we don't want to fail the function if email fails
        }

        // Send confirmation email to the user (if they provided an email)
        if (user_email && user_email.trim().length > 0) {
            const userConfirmationSubject = "Thank you for your feedback - Badya";
            const userConfirmationText = `Hello ${user_display_name || "there"},

Thank you for taking the time to submit feedback about Badya. We've received your message and will review it soon.

Your feedback helps us improve the app for everyone.

Best regards,
The Badya Team`;

            const userMailOptions = {
                from: gmailUser,
                to: user_email,
                subject: userConfirmationSubject,
                text: userConfirmationText,
            };

            try {
                await transporter.sendMail(userMailOptions);
                logger.info(`Confirmation email sent to user ${user_email} for report ${reportId}`);
            } catch (error) {
                logger.error(`Error sending confirmation email to user: ${error}`);
                // Don't throw - user confirmation is nice to have but not critical
            }
        } else {
            logger.info(`Skipping user confirmation email - no user email provided for report ${reportId}`);
        }
    }
);

