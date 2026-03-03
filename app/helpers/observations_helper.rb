module ObservationsHelper
  include ActionView::RecordIdentifier

  def observation_card_frame_id(observation, prefix = nil)
    prefixed_dom_id("#{dom_id(observation)}_card", prefix)
  end

  def observation_card_container_id(observation, prefix = nil)
    prefixed_dom_id("#{dom_id(observation)}_card_container", prefix)
  end

  def observation_card_context_params(frame_id_prefix: nil, entry_dom_id_prefix: nil)
    {}.tap do |params|
      params[:frame_id_prefix] = frame_id_prefix.to_s if frame_id_prefix.to_s.present?
      params[:entry_dom_id_prefix] = entry_dom_id_prefix.to_s if entry_dom_id_prefix.to_s.present?
    end
  end

  def prefixed_dom_id(base_id, prefix)
    prefix_str = prefix.to_s
    return base_id if prefix_str.blank?

    "#{prefix_str}_#{base_id}"
  end
end
