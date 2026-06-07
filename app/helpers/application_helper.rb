module ApplicationHelper
  def sidebar_link(label, path, id)
    active = current_page?(path)
    base = "relative flex items-center gap-2.5 h-8 px-3 rounded-md text-[13px] no-underline transition-all duration-150"
    classes = if active
      "#{base} sidebar-active"
    else
      "#{base} text-text-soft hover:text-text-primary hover:bg-bg"
    end
    link_to label, path, class: classes, data: { id: id }
  end

  def card(title: nil, action: nil, classes: "", &block)
    content_tag :div, class: "card #{classes}" do
      content_tag :div, class: "relative p-5" do
        out = "".html_safe
        if title
          out += content_tag(:div, class: "flex items-center justify-between mb-4") {
            h = content_tag(:p, title, class: "text-[12px] font-semibold tracking-[0.02em] uppercase text-text-muted m-0")
            h += action if action
            h
          }
        end
        out += capture(&block)
        out
      end
    end
  end

  def status_pill(text, color: :success)
    colors = {
      success: "pill-ready",
      warning: "pill-warning",
      danger: "pill-danger",
      info: "pill-running"
    }
    content_tag :span, text, class: "inline-flex items-center h-[22px] px-2 rounded-md text-[11px] font-semibold #{colors[color]}"
  end

  def risk_color(level)
    case level&.downcase
    when "low" then "text-success"
    when "medium" then "text-warning"
    when "high" then "text-danger"
    else "text-text-muted"
    end
  end
end
