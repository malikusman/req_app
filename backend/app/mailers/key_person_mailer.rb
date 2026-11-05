# frozen_string_literal: true

# Invitations to the conversations with leadership (Doc 14 §4.1): from the
# company, working with Mjadi; what it's for; how long; one link. Never mentions
# automation, assessment or consultants. In the person's own language.
class KeyPersonMailer < ApplicationMailer
  # The key user: their conversation is waiting in the portal.
  def ready(participant)
    setup(participant)
    @url = "#{NotificationService.app_host}/company/leadership"
    mail(to: participant.email, subject: subject("ready"))
  end

  # Another manager: a link of their own.
  def invitation(participant, url)
    setup(participant)
    @url = url
    @scope = participant.scope.presence || participant.department.presence
    mail(to: participant.email, subject: subject("invitation"))
  end

  private

  def setup(participant)
    @participant = participant
    @company_name = participant.company.display_name.presence || participant.company.name
    @key_user_name = participant.engagement.key_user&.name
    @arabic = participant.preferred_language.to_s.start_with?("ar")
  end

  def subject(kind)
    if @arabic
      kind == "ready" ? "حديثك مع Mjadi جاهز" : "#{@company_name} و Mjadi: هل لديك خمس عشرة دقيقة؟"
    else
      kind == "ready" ? "Your conversation with Mjadi is ready" : "#{@company_name} and Mjadi: fifteen minutes of your time?"
    end
  end
end
